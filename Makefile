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
	docker_login \
	fix_volume_perms \
	deployments/docker-compose/files/dashboards/nest-thermostat-fahrenheit.json \
	deployments/docker-compose/files/dashboards/nest-thermostat.json \
	format \
	golangci-lint \
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

docker_login: test_auth
	docker login -u "$$(cat ~/.secrets/docker_username)" --password-stdin        < ~/.secrets/docker_pull_dhi_token
	docker login -u "$$(cat ~/.secrets/docker_username)" --password-stdin dhi.io < ~/.secrets/docker_pull_dhi_token

deploy:	docker_login undeploy fix_volume_perms clean build_docker sanitize_dashboard convert_dashboard_from_c_to_f
	docker compose -f deployments/docker-compose/docker-compose.yml up --pull always -d

deploy_fahrenheit: docker_login undeploy fix_volume_perms clean build_docker sanitize_dashboard convert_dashboard_from_c_to_f
	docker compose \
		-f deployments/docker-compose/docker-compose.yml \
		-f deployments/docker-compose/docker-compose-fahrenheit.yml \
		up --pull always -d

undeploy:
	docker compose -f deployments/docker-compose/docker-compose.yml down

# Docker Hardened Images (dhi.io/*) run as the non-root user 65532, but the
# persisted volumes may have last been written by a different image user (the
# upstream prom/prometheus image runs as nobody, 65534). When that happens the
# DHI runtime image crash-loops on startup, e.g.:
#     err="open /var/prometheus/queries.active: permission denied"
#     msg="failed to initialize active query tracker"
# Re-own the named volumes to the DHI runtime user before deploy. Absent
# volumes are skipped: Docker seeds them from the image on first mount, so a
# chown on an empty volume would not stick.
nonroot_uid := 65532
nonroot_gid := 65532

fix_volume_perms:
	@for v in docker-compose_prometheus-data-volume; do \
		if docker volume inspect "$$v" >/dev/null 2>&1; then \
			echo "fix_volume_perms: chown $$v -> $(nonroot_uid):$(nonroot_gid)"; \
			docker run --rm -v "$$v:/mnt" alpine:latest \
				chown -R $(nonroot_uid):$(nonroot_gid) /mnt; \
		else \
			echo "fix_volume_perms: $$v absent, skipping"; \
		fi; \
	done

upgrade_go_dependencies:
	go get -u ./...
	go get -u=patch ./...
	go get -u all
	go mod tidy

format:
	find . -iname \*.go -exec gofmt -s -w {} \;
	go mod tidy

golangci-lint:
	golangci-lint run ./...

lint: golangci-lint
	go install honnef.co/go/tools/cmd/staticcheck@latest
	staticcheck ./...

log:
	docker logs docker-compose-pronestheus-1 -f

test: test_auth
	CGO_ENABLED=0 GOOS=linux go test ./... -v

test_auth:
	@ for s in pronestheus_nest_client_id \
		pronestheus_nest_client_secret \
		pronestheus_nest_project_id \
		pronestheus_nest_refresh_token \
		docker_username \
		docker_pull_dhi_token; do \
		test -s "$$HOME/.secrets/$$s" || { echo "Missing required secret: $$s" >&2; exit 1; }; \
	done
	@ for s in pronestheus_owm_auth pronestheus_owm_location; do \
		test -s "$$HOME/.secrets/$$s" || echo "Warning: missing optional secret $$s" >&2; \
	done
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
