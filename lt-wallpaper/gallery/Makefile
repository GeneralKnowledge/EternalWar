.PHONY: run health install-deps docker-build docker-up docker-down

run:
	./scripts/run.sh

health:
	curl -sS http://127.0.0.1:$${LT_GALLERY_PORT:-8080}/api/health | python3 -m json.tool

install-deps:
	sudo ./scripts/install-deps.sh

docker-build:
	docker compose build

docker-up:
	docker compose up -d --build

docker-down:
	docker compose down
