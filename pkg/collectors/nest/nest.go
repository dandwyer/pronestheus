package nest

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/tidwall/gjson"

	"golang.org/x/oauth2"
	"golang.org/x/oauth2/endpoints"

	"github.com/go-kit/log"

	"github.com/pkg/errors"
	"github.com/prometheus/client_golang/prometheus"
)

var (
	errNon200Response      = errors.New("nest API responded with non-200 code")
	errFailedParsingURL    = errors.New("failed parsing OpenWeatherMap API URL")
	errFailedUnmarshalling = errors.New("failed unmarshalling Nest API response body")
	errFailedRequest       = errors.New("failed Nest API request")
	errFailedReadingBody   = errors.New("failed reading Nest API response body")
)

// Thermostat stores thermostat data received from Nest API.
type Thermostat struct {
	ID                  string
	Label               string
	AmbientTemp         float64
	HeatSetpointTemp    float64
	CoolSetpointTemp    float64
	Humidity            float64
	Status              string
	Mode                string
	EcoMode             string
	EcoHeatSetpointTemp float64
	EcoCoolSetpointTemp float64
	FanTimerMode        string
}

// Config provides the configuration necessary to create the Collector.
type Config struct {
	Logger            log.Logger
	Timeout           int
	APIURL            string
	OAuthClientID     string
	OAuthClientSecret string
	RefreshToken      string
	ProjectID         string
	OAuthToken        *oauth2.Token
}

// Collector implements the Collector interface, collecting thermostats data from Nest API.
type Collector struct {
	client  *http.Client
	url     string
	logger  log.Logger
	metrics *Metrics
}

// Metrics contains the metrics collected by the Collector.
type Metrics struct {
	up                  *prometheus.Desc
	ambientTemp         *prometheus.Desc
	heatSetpointTemp    *prometheus.Desc
	coolSetpointTemp    *prometheus.Desc
	humidity            *prometheus.Desc
	status              *prometheus.Desc
	mode                *prometheus.Desc
	ecoMode             *prometheus.Desc
	ecoHeatSetpointTemp *prometheus.Desc
	ecoCoolSetpointTemp *prometheus.Desc
	fanTimerMode        *prometheus.Desc
}

// New creates a Collector using the given Config.
func New(cfg Config) (*Collector, error) {
	if _, err := url.ParseRequestURI(cfg.APIURL); err != nil {
		return nil, errors.Wrap(errFailedParsingURL, err.Error())
	}

	oauthConfig := &oauth2.Config{
		ClientID:     cfg.OAuthClientID,
		ClientSecret: cfg.OAuthClientSecret,
		Scopes:       []string{"https://www.googleapis.com/auth/sdm.service"},
		Endpoint:     endpoints.Google,
	}

	// If token is not provided we create a new one using RefreshToken. Using this token, the client will automatically
	// get, and refresh, a valid access token for the API.
	if cfg.OAuthToken == nil {
		cfg.OAuthToken = &oauth2.Token{
			TokenType:    "Bearer",
			RefreshToken: cfg.RefreshToken,
		}
	}

	client := oauthConfig.Client(context.Background(), cfg.OAuthToken)
	client.Timeout = time.Duration(cfg.Timeout) * time.Millisecond

	collector := &Collector{
		client:  client,
		url:     strings.TrimRight(cfg.APIURL, "/") + "/enterprises/" + cfg.ProjectID + "/devices/",
		logger:  cfg.Logger,
		metrics: buildMetrics(),
	}

	return collector, nil
}

func buildMetrics() *Metrics {
	var nestLabels = []string{"id", "label"}
	return &Metrics{
		up:                  prometheus.NewDesc(strings.Join([]string{"nest", "up"}, "_"), "Was talking to Nest API successful.", nil, nil),
		ambientTemp:         prometheus.NewDesc(strings.Join([]string{"nest", "ambient", "temperature", "celsius"}, "_"), "Inside temperature.", nestLabels, nil),
		heatSetpointTemp:    prometheus.NewDesc(strings.Join([]string{"nest", "heat", "setpoint", "temperature", "celsius"}, "_"), "Heat setpoint temperature.", nestLabels, nil),
		coolSetpointTemp:    prometheus.NewDesc(strings.Join([]string{"nest", "cool", "setpoint", "temperature", "celsius"}, "_"), "Cool setpoint temperature.", nestLabels, nil),
		humidity:            prometheus.NewDesc(strings.Join([]string{"nest", "humidity", "percent"}, "_"), "Inside humidity.", nestLabels, nil),
		status:              prometheus.NewDesc(strings.Join([]string{"nest", "status"}, "_"), "Thermostat status.", []string{"id", "label", "mode"}, nil),
		mode:                prometheus.NewDesc(strings.Join([]string{"nest", "mode"}, "_"), "Thermostat mode.", []string{"id", "label", "mode"}, nil),
		ecoMode:             prometheus.NewDesc(strings.Join([]string{"nest", "eco", "mode"}, "_"), "Thermostat eco mode.", []string{"id", "label", "mode"}, nil),
		ecoHeatSetpointTemp: prometheus.NewDesc(strings.Join([]string{"nest", "eco", "heat", "setpoint", "temperature", "celsius"}, "_"), "Eco heat setpoint temperature.", nestLabels, nil),
		ecoCoolSetpointTemp: prometheus.NewDesc(strings.Join([]string{"nest", "eco", "cool", "setpoint", "temperature", "celsius"}, "_"), "Eco cool setpoint temperature.", nestLabels, nil),
		fanTimerMode:        prometheus.NewDesc(strings.Join([]string{"nest", "fan", "timer", "mode"}, "_"), "Thermostat fan timer mode.", []string{"id", "label", "mode"}, nil),
	}
}

// Describe implements the prometheus.Describe interface.
func (c *Collector) Describe(ch chan<- *prometheus.Desc) {
	ch <- c.metrics.up
	ch <- c.metrics.ambientTemp
	ch <- c.metrics.heatSetpointTemp
	ch <- c.metrics.coolSetpointTemp
	ch <- c.metrics.humidity
	ch <- c.metrics.status
	ch <- c.metrics.mode
	ch <- c.metrics.ecoMode
	ch <- c.metrics.ecoHeatSetpointTemp
	ch <- c.metrics.ecoCoolSetpointTemp
	ch <- c.metrics.fanTimerMode
}

// Collect implements the prometheus.Collector interface.
func (c *Collector) Collect(ch chan<- prometheus.Metric) {
	thermostats, err := c.getNestReadings()
	if err != nil {
		ch <- prometheus.MustNewConstMetric(c.metrics.up, prometheus.GaugeValue, 0)
		c.logger.Log("level", "error", "message", "Failed collecting Nest data", "stack", errors.WithStack(err))
		return
	}

	c.logger.Log("level", "debug", "message", "Successfully collected Nest data")

	ch <- prometheus.MustNewConstMetric(c.metrics.up, prometheus.GaugeValue, 1)

	for _, therm := range thermostats {
		labels := []string{therm.ID, strings.Replace(therm.Label, " ", "-", -1)}

		ch <- prometheus.MustNewConstMetric(c.metrics.ambientTemp, prometheus.GaugeValue, therm.AmbientTemp, labels...)
		ch <- prometheus.MustNewConstMetric(c.metrics.heatSetpointTemp, prometheus.GaugeValue, therm.HeatSetpointTemp, labels...)
		ch <- prometheus.MustNewConstMetric(c.metrics.coolSetpointTemp, prometheus.GaugeValue, therm.CoolSetpointTemp, labels...)
		ch <- prometheus.MustNewConstMetric(c.metrics.humidity, prometheus.GaugeValue, therm.Humidity, labels...)
		ch <- prometheus.MustNewConstMetric(c.metrics.status, prometheus.GaugeValue, 1, append(labels, therm.Status)...)
		ch <- prometheus.MustNewConstMetric(c.metrics.mode, prometheus.GaugeValue, 1, append(labels, therm.Mode)...)
		ch <- prometheus.MustNewConstMetric(c.metrics.ecoMode, prometheus.GaugeValue, 1, append(labels, therm.EcoMode)...)
		ch <- prometheus.MustNewConstMetric(c.metrics.ecoHeatSetpointTemp, prometheus.GaugeValue, therm.EcoHeatSetpointTemp, labels...)
		ch <- prometheus.MustNewConstMetric(c.metrics.ecoCoolSetpointTemp, prometheus.GaugeValue, therm.EcoCoolSetpointTemp, labels...)
		ch <- prometheus.MustNewConstMetric(c.metrics.fanTimerMode, prometheus.GaugeValue, 1, append(labels, therm.FanTimerMode)...)
	}
}

func (c *Collector) getNestReadings() (thermostats []*Thermostat, err error) {
	res, err := c.client.Get(c.url)
	if err != nil {
		return nil, errors.Wrap(errFailedRequest, err.Error())
	}

	if res.StatusCode != 200 {
		return nil, errors.Wrap(errNon200Response, fmt.Sprintf("code: %d", res.StatusCode))
	}

	defer res.Body.Close()

	body, err := io.ReadAll(res.Body)
	if err != nil {
		return nil, errors.Wrap(errFailedReadingBody, err.Error())
	}

	// Iterate over the array of "devices" returned from the API and unmarshall them into Thermostat objects.
	gjson.Get(string(body), "devices").ForEach(func(_, device gjson.Result) bool {
		// Skip to next device if the current one is not a thermostat.
		if device.Get("type").String() != "sdm.devices.types.THERMOSTAT" {
			return true
		}

		thermostat := Thermostat{
			ID:                  device.Get("name").String(),
			Label:               device.Get("traits.sdm\\.devices\\.traits\\.Info.customName").String(),
			AmbientTemp:         device.Get("traits.sdm\\.devices\\.traits\\.Temperature.ambientTemperatureCelsius").Float(),
			HeatSetpointTemp:    device.Get("traits.sdm\\.devices\\.traits\\.ThermostatTemperatureSetpoint.heatCelsius").Float(),
			CoolSetpointTemp:    device.Get("traits.sdm\\.devices\\.traits\\.ThermostatTemperatureSetpoint.coolCelsius").Float(),
			Humidity:            device.Get("traits.sdm\\.devices\\.traits\\.Humidity.ambientHumidityPercent").Float(),
			Status:              device.Get("traits.sdm\\.devices\\.traits\\.ThermostatHvac.status").String(),
			Mode:                device.Get("traits.sdm\\.devices\\.traits\\.ThermostatMode.mode").String(),
			EcoMode:             device.Get("traits.sdm\\.devices\\.traits\\.ThermostatEco.mode").String(),
			EcoHeatSetpointTemp: device.Get("traits.sdm\\.devices\\.traits\\.ThermostatEco.heatCelsius").Float(),
			EcoCoolSetpointTemp: device.Get("traits.sdm\\.devices\\.traits\\.ThermostatEco.coolCelsius").Float(),
			FanTimerMode:        device.Get("traits.sdm\\.devices\\.traits\\.Fan.timerMode").String(),
		}

		thermostats = append(thermostats, &thermostat)
		return true
	})

	if len(thermostats) == 0 {
		return nil, errors.Wrap(errFailedUnmarshalling, "no valid thermostats in devices list")
	}

	return thermostats, nil
}
