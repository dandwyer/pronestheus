# https://www.gnu.org/software/make/manual/make.html

.PHONY: all build build_docker deploy undeploy test test_auth clean

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
	

clean:
	rm $(shell pwd)/pronestheus
