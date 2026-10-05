# ProNestheus

![build](https://github.com/dandwyer/pronestheus/workflows/build/badge.svg)

A Prometheus exporter for the [Nest Learning Thermostat](https://nest.com/). Exposes metrics about your thermostats and the weather in your current location.

Works with the new [Google Smart Device Management API](https://developers.google.com/nest/device-access)!

![dashboard](https://raw.githubusercontent.com/dandwyer/pronestheus/refs/heads/main/docs/dashboard.png)

## Installation

### Binary download

Grab the Linux, macOS or Windows executable from the [latest release](https://github.com/dandwyer/pronestheus/releases/latest).

### Docker image

```bash
docker run -p 9777:9777 \
  -e PRONESTHEUS_NEST_CLIENT_ID=xxx \
  -e PRONESTHEUS_NEST_CLIENT_SECRET=xxx \
  -e PRONESTHEUS_NEST_PROJECT_ID=xxx \
  -e PRONESTHEUS_NEST_REFRESH_TOKEN=xxx \
  -e PRONESTHEUS_OWM_AUTH=xxx \
  dandw/pronestheus
```

Each credential can also be supplied from a file by appending `_FILE` to the
variable name. For example:
`-e PRONESTHEUS_NEST_CLIENT_ID_FILE=/run/secrets/pronestheus_nest_client_id`.

### "One-click" installation with Docker Compose

Store your secrets as snake_case files in `~/.secrets/` (e.g.
`pronestheus_nest_client_id`; see the `secrets:` section in
`deployments/docker-compose/docker-compose.yml`). You also need Docker registry
credentials, `docker_username` and `docker_pull_dhi_token`, so `make deploy` can
authenticate to [Docker Hardened Images](https://dhi.io/) before pulling its base
images.

Set the permissions so the directory stays private but the files are readable by
the container (the Docker credential files are only read on the host, so they can
stay `600`):

```bash
chmod 700 ~/.secrets
chmod 644 ~/.secrets/pronestheus_*
```

The ProNestheus image runs as `nonroot` (UID 65532), and Docker Compose mounts
each `file:` secret with its host permissions (unlike `docker stack deploy`, which
mounts secrets as world-readable `0444`). The `700` directory keeps other host
users out; the `644` files let the container read them.

To confirm that all authentication prerequisites are in place before deploying, run:
```bash
make test_auth
```
This verifies every mandatory secret (Nest credentials and Docker registry
credentials) and warns about any missing optional ones.

Then start the stack. Either use Docker Compose directly:
```
cd deployments/docker-compose
docker compose up
```
or, from the repository root, use the Make targets for Celsius and Fahrenheit support, respectively:
```
make deploy
make deploy_fahrenheit
```

This will start docker containers with Prometheus, Grafana and ProNestheus exporter automatically configured. Visit http://localhost:3000 to open Grafana dashboard with your thermostat metrics.

### Usage and configuration

All configuration flags can be passed as environment variables with the
`PRONESTHEUS_` prefix (e.g. `PRONESTHEUS_OWM_AUTH`). Appending `_FILE` to a
variable name reads the value from the file it points to (e.g.
`PRONESTHEUS_NEST_CLIENT_ID_FILE=/run/secrets/pronestheus_nest_client_id`), which
is how the bundled Docker Compose setup injects secrets.

```
usage: pronestheus [<flags>]

Flags:
  -h, --help                     Show context-sensitive help (also try --help-long and --help-man).
      --listen-addr=":9777"      Address on which to expose metrics and web interface.
      --metrics-path="/metrics"  Path under which to expose metrics.
      --scrape-timeout=5000      Time to wait for remote APIs to response, in milliseconds.
      --nest-url="https://smartdevicemanagement.googleapis.com/v1/"
                                 Nest API URL.
      --nest-client-id=NEST-CLIENT-ID
                                 OAuth2 Client ID
      --nest-client-secret=NEST-CLIENT-SECRET
                                 OAuth2 Client Secret.
      --nest-project-id=NEST-PROJECT-ID
                                 Device Access Project ID.
      --nest-refresh-token=NEST-REFRESH-TOKEN
                                 Refresh token
      --owm-url="http://api.openweathermap.org/data/2.5/weather"
                                 The OpenWeatherMap API URL.
      --owm-auth=OWM-AUTH        The authorization token for OpenWeatherMap API.
      --owm-location="2759794"   The location ID for OpenWeatherMap API. Defaults to Amsterdam.
  -v, --version                  Show application version.

```

### Authentication

To be able to call the Nest API you need to register for Device Access with Google (there's a one-time $5 fee) and follow [the Get Started guide](https://developers.google.com/nest/device-access/get-started) to create a Device Access project and OAuth2 client.

Then, follow the [Authorize the account guide](https://developers.google.com/nest/device-access/authorize) to get the necessary values for:
* OAuth2 Client ID
* OAuth2 Client Secret
* Device Access Project ID
* OAuth2 Refresh Token

Because ProNestheus is meant to run continuously, it doesn't require OAuth2 Access Token, only the Refresh Token. It will automatically get the valid access token and refresh it when needed.

OpenWeatherMap API key is required to call the weather API. [Look here](https://openweathermap.org/appid) for instructions on how to get it.

## Exported metrics

```
# HELP nest_ambient_temperature_celsius Inside temperature.
# TYPE nest_ambient_temperature_celsius gauge
nest_ambient_temperature_celsius{id="abcd1234",label="Living-Room"} 23.5
# HELP nest_status thermostat status.
# TYPE nest_status gauge
nest_status{id="abcd1234",label="Living-Room",mode="HEATING"} 1
# HELP nest_humidity_percent Inside humidity.
# TYPE nest_humidity_percent gauge
nest_humidity_percent{id="abcd1234",label="Living-Room"} 55
# HELP nest_heat_setpoint_temperature_celsius Setpoint temperature.
# TYPE nest_heat_setpoint_temperature_celsius gauge
nest_heat_setpoint_temperature_celsius{id="abcd1234",label="Living-Room"} 18
# HELP nest_cool_setpoint_temperature_celsius Setpoint temperature.
# TYPE nest_cool_setpoint_temperature_celsius gauge
nest_cool_setpoint_temperature_celsius{id="abcd1234",label="Living-Room"} 21
# HELP nest_mode Thermostat mode.
# TYPE nest_mode gauge
nest_mode{id="abcd1234",label="Living-Room",mode="HEATCOOL"} 1
# HELP nest_eco_cool_setpoint_temperature_celsius Eco cool setpoint temperature.
# TYPE nest_eco_cool_setpoint_temperature_celsius gauge
nest_eco_cool_setpoint_temperature_celsius{id="abcd1234",label="Living-Room"} 24
# HELP nest_eco_heat_setpoint_temperature_celsius Eco heat setpoint temperature.
# TYPE nest_eco_heat_setpoint_temperature_celsius gauge
nest_eco_heat_setpoint_temperature_celsius{id="abcd1234",label="Living-Room"} 18
# HELP nest_eco_mode Thermostat eco mode.
# TYPE nest_eco_mode gauge
nest_eco_mode{id="abcd1234",label="Living-Room",mode="OFF"} 1
# HELP nest_fan_timer_mode Thermostat fan timer mode.
# TYPE nest_fan_timer_mode gauge
nest_fan_timer_mode{id="abcd1234",label="Living-Room",mode="OFF"} 1
# HELP nest_up Was talking to Nest API successful.
# TYPE nest_up gauge
nest_up 1
# HELP nest_weather_humidity_percent Outside humidity.
# TYPE nest_weather_humidity_percent gauge
nest_weather_humidity_percent 82
# HELP nest_weather_pressure_hectopascal Outside pressure.
# TYPE nest_weather_pressure_hectopascal gauge
nest_weather_pressure_hectopascal 1016
# HELP nest_weather_temperature_celsius Outside temperature.
# TYPE nest_weather_temperature_celsius gauge
nest_weather_temperature_celsius 17.57
# HELP nest_weather_up Was talking to OpenWeatherMap API successful.
# TYPE nest_weather_up gauge
nest_weather_up 1
```

## Releasing

To create a release:
* Test locally
* Push your latest code
* Verify that all workflows succeed
* Navigate to [Releases](https://github.com/dandwyer/pronestheus/releases) page and hit "Draft a new release" button
* For Tag button, choose "Create a new tag" option and borrow semantic versioning convention from adjacent releases

Note: the release workflow needs the `DOCKER_PASSWORD` secret and `DOCKER_USERNAME`
repository variable to push to Docker Hub and to authenticate to Docker Hardened
Images (`dhi.io`, used for the base image); the `DOCKER_PASSWORD` PAT must be
entitled to pull DHI images. `GITHUB_TOKEN` is provided automatically.
