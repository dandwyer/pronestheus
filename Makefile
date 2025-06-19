# https://www.gnu.org/software/make/manual/make.html

.PHONY: all build build_docker deploy deploy_fahrenheit undeploy \
	log test test_auth \
	sanitize_dashboard \
	deployments/docker-compose/files/dashboards/nest-thermostat-fahrenheit.json \
	convert_dashboard clean

all: build test

build:
	go build -C cmd/pronestheus -o $(shell pwd)/pronestheus

build_docker: build
	docker build -t maxpower47/pronestheus:latest .

deploy:	undeploy clean build_docker sanitize_dashboard convert_dashboard
	docker compose -f deployments/docker-compose/docker-compose.yml up -d

deploy_fahrenheit: undeploy clean build_docker sanitize_dashboard convert_dashboard
	docker compose \
		-f deployments/docker-compose/docker-compose.yml \
		-f deployments/docker-compose/docker-compose-fahrenheit.yml \
		up -d

undeploy:
	docker compose -f deployments/docker-compose/docker-compose.yml down

log:
	docker logs docker-compose-pronestheus-1 -f

test: test_auth
	CGO_ENABLED=0 GOOS=linux go test ./... -v

test_auth:
	@ . deployments/docker-compose/.env; echo $${PRONESTHEUS_NEST_CLIENT_ID:?Needs to be set} STDOUT>/dev/null
	@ . deployments/docker-compose/.env; echo $${PRONESTHEUS_NEST_CLIENT_SECRET:?Needs to be set} STDOUT>/dev/null
	@ . deployments/docker-compose/.env; echo $${PRONESTHEUS_NEST_PROJECT_ID:?Needs to be set} STDOUT>/dev/null
	@ . deployments/docker-compose/.env; echo $${PRONESTHEUS_NEST_REFRESH_TOKEN:?Needs to be set} STDOUT>/dev/null
	@ - . deployments/docker-compose/.env; echo $${PRONESTHEUS_OWM_AUTH:?Should be set} STDOUT>/dev/null
	@ - . deployments/docker-compose/.env; echo $${PRONESTHEUS_OWM_LOCATION:?Should be set} STDOUT>/dev/null
	@ echo "All mandatory environment variables are set."

# If you export dashboard JSON from Grafana, you need to sanitize it to get rid
# of uid and datasource fields that are not needed in the provisioning artifact.
sanitize_dashboard: deployments/docker-compose/files/dashboards/nest-thermostat.json
	jq '.time.from = "now-1h"' $< | sponge $<
	jq '.time.to = "now"' $< | sponge $<
	jq '.title = "Nest Thermostat"' $< | sponge $<
	jq '.version = 1' $< | sponge $<
	jq 'del(.. | objects | .datasource?)' $< | sponge $<
	jq 'del(.. | objects | .uid?)' $< | sponge $<

convert_dashboard : deployments/docker-compose/files/dashboards/nest-thermostat-fahrenheit.json

deployments/docker-compose/files/dashboards/nest-thermostat-fahrenheit.json: \
	deployments/docker-compose/files/dashboards/nest-thermostat.json
	jq "walk(if type == \"object\" and has(\"expr\") and (.expr | test(\"^[a-z_]+_celsius\")) \
		then .expr |= sub(\"(?<x>[a-z_]+_celsius.*)\"; \"((\\(.x)) * 1.8) + 32\") \
		else . end)" $< | sponge $@
	jq "walk(if type == \"object\" and has(\"unit\") and (.unit | test(\"^celsius\")) \
		then .unit |= sub(\"celsius\"; \"fahrenheit\") \
		else . end)" $@ | sponge $@
	jq "walk(if type == \"object\" and (.unit == \"fahrenheit\") and has(\"min\") and has(\"max\") \
		then \
			.min = ((.min * 1.8) + 32) | \
			.max = ((.max * 1.8) + 32) | \
			.thresholds.steps = ( \
				.thresholds.steps | map( \
					if has(\"value\") then .value = ((.value * 1.8) + 32) else . end \
				) \
			) \
		else . end)" $@ | sponge $@
	jq '.title = "Nest Thermostat (F)"' $@ | sponge $@

clean:
	rm $(shell pwd)/pronestheus
