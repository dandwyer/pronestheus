# https://www.gnu.org/software/make/manual/make.html

.PHONY: all build build_docker deploy undeploy test test_auth sanitize_dashboard clean

all: build test

build:
	go build -C cmd/pronestheus -o $(shell pwd)/pronestheus

build_docker: build
	docker build -t maxpower47/pronestheus:latest .

deploy:	undeploy clean build_docker
	docker compose -f deployments/docker-compose/docker-compose.yml up -d

undeploy:
	docker compose -f deployments/docker-compose/docker-compose.yml down

make log:
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
sanitize_dashboard: deployments/docker-compose/files/grafana-dashboard.json
	jq '.time.from = "now-1h"' $< | sponge $<
	jq '.time.to = "now"' $< | sponge $<
	jq '.title = "Nest Thermostat"' $< | sponge $<
	jq '.version = 1' $< | sponge $<
	jq 'del(.. | objects | .datasource?)' $< | sponge $<
	jq 'del(.. | objects | .uid?)' $< | sponge $<

clean:
	rm $(shell pwd)/pronestheus
