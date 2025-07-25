# https://www.gnu.org/software/make/manual/make.html

.PHONY: \
	all \
	analyze \
	build \
	build_docker \
	clean \
	convert_dashboard_from_c_to_f \
	convert_dashboard_from_f_to_c \
	deploy \
	deploy_fahrenheit \
	deployments/docker-compose/files/dashboards/nest-thermostat-fahrenheit.json \
	deployments/docker-compose/files/dashboards/nest-thermostat.json \
	format \
	lint \
	log \
	sanitize_dashboard \
	test \
	test_auth \
	undeploy \

all: build test

analyze:
	cd cmd/pronestheus; goweight .

build:
	CGO_ENABLED=0 GOOS=linux go build -C cmd/pronestheus -ldflags="-s -w" -trimpath -o $(shell pwd)/pronestheus

build_docker: build test
	docker build -t dandw/pronestheus:latest .

deploy:	undeploy clean build_docker sanitize_dashboard convert_dashboard_from_c_to_f test_auth
	docker compose -f deployments/docker-compose/docker-compose.yml up -d

deploy_fahrenheit: undeploy clean build_docker sanitize_dashboard convert_dashboard_from_c_to_f test_auth
	docker compose \
		-f deployments/docker-compose/docker-compose.yml \
		-f deployments/docker-compose/docker-compose-fahrenheit.yml \
		up -d

undeploy:
	docker compose -f deployments/docker-compose/docker-compose.yml down

upgrade_go_dependencies:
	go get -u ./...
	go get -u=patch ./...
	go get -u all
	go mod tidy

format:
	find . -iname \*.go -exec gofmt -s -w {} \;
	go mod tidy

lint:
	go install honnef.co/go/tools/cmd/staticcheck@latest
	staticcheck ./...

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
	jq '.time.from = "now-7d"' $< | sponge $<
	jq '.time.to = "now"' $< | sponge $<
	jq '.title = "Nest Thermostat"' $< | sponge $<
	jq '.version = 1' $< | sponge $<
	jq 'del(.. | objects | .datasource?)' $< | sponge $<

convert_dashboard_from_c_to_f : deployments/docker-compose/files/dashboards/nest-thermostat-fahrenheit.json

convert_dashboard_from_f_to_c: deployments/docker-compose/files/dashboards/nest-thermostat.json

deployments/docker-compose/files/dashboards/nest-thermostat-fahrenheit.json: sanitize_dashboard
	jq "walk(if type == \"object\" and has(\"expr\") and (.expr | test(\"^[a-z_]+_celsius\")) \
		then .expr |= sub(\"(?<x>[a-z_]+_celsius.*)\"; \"((\\(.x)) * 1.8) + 32\") \
		else . end)" deployments/docker-compose/files/dashboards/nest-thermostat.json | sponge $@
	jq "walk(if type == \"object\" and has(\"unit\") and (.unit | test(\"^celsius\")) \
		then .unit |= sub(\"celsius\"; \"fahrenheit\") \
		else . end)" $@ | sponge $@
	jq "walk(if type == \"object\" and (.unit == \"fahrenheit\") and has(\"min\") and has(\"max\") \
		then \
			.min = (((((.min * 1.8) + 32) * 10) | round) / 10) | \
			.max = (((((.max * 1.8) + 32) * 10) | round) / 10) | \
			.thresholds.steps = ( \
				.thresholds.steps | map( \
					if has(\"value\") then .value = ((.value * 1.8) + 32) else . end \
				) \
			) \
		else . end)" $@ | sponge $@
	jq '.title = "Nest Thermostat (F)"' $@ | sponge $@
	jq '.uid |= sub("(?<x>.*)-c"; "\(.x)-f")' $@ | sponge $@

deployments/docker-compose/files/dashboards/nest-thermostat.json:
	jq "walk(if type == \"object\" and has(\"expr\") and (.expr | test(\"[a-z_]+_celsius\")) \
		then .expr |= sub(\"\\\\(\\\\((?<x>[a-z_]+_celsius( > 0)?).*\"; \"\\(.x)\") \
		else . end)" deployments/docker-compose/files/dashboards/nest-thermostat-fahrenheit.json | sponge $@
	jq "walk(if type == \"object\" and has(\"unit\") and (.unit | test(\"^fahrenheit\")) \
		then .unit |= sub(\"fahrenheit\"; \"celsius\") \
		else . end)" $@ | sponge $@
	jq "walk(if type == \"object\" and (.unit == \"celsius\") and has(\"min\") and has(\"max\") \
		then \
			.min = (((.min - 32) / 1.8) | round) | \
			.max = (((.max - 32) / 1.8) | round) | \
			.thresholds.steps = ( \
				.thresholds.steps | map( \
					if has(\"value\") then .value = (((.value - 32) / 1.8) | round) else . end \
				) \
			) \
		else . end)" $@ | sponge $@
	jq '.title = "Nest Thermostat"' $@ | sponge $@
	jq '.uid |= sub("(?<x>.*)-f"; "\(.x)-c")' $@ | sponge $@

clean:
	- rm $(shell pwd)/pronestheus
