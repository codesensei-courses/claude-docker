.PHONY: clean deploy claude build run claude-state

deploy:
	./deploy.sh

zip:
	mkdir -p cursus_zip
	publishing/mkzip.sh

new:
	./new_course.sh

clean:
	rm -rf deploy cursus_zip
	rm ~/.org-timestamps/*.cache
	mkdir -p deploy

build:
	docker build . --tag=live-courses:latest

claude-state:
	# Ensure the host state files exist before `docker run`. Docker
	# auto-creates missing bind-mount sources as directories, which would
	# break the file-level mounts in `run` / `claude`. Both files must be
	# bind-mounted (not symlinks inside the container) because Claude Code
	# writes them via atomic rename, which replaces symlinks with regular
	# files and detaches them from the persisted host file.
	#
	# .credentials.json holds the OAuth token; .claude.json holds user/login
	# state (userID, email, onboarding flags, theme, project history). Claude
	# needs both to recognize a persisted login — the token alone is not
	# enough, since startup checks the user state in .claude.json first.
	mkdir -p ~/.claude-docker
	touch ~/.claude-docker/.credentials.json ~/.claude-docker/.claude.json
	chmod 600 ~/.claude-docker/.credentials.json

run: claude-state
	docker run -it \
		--mount type=bind,source=.,destination=/home/codesensei/live_courses \
		-v ~/.claude-docker/.credentials.json:/home/codesensei/.claude/.credentials.json \
		-v ~/.claude-docker/.claude.json:/home/codesensei/.claude.json \
		live-courses

claude: claude-state
	docker exec -it live-courses tmux attach 2>/dev/null || \
	docker run -it --rm --name live-courses \
		--mount type=bind,source=.,destination=/home/codesensei/project/ \
		-v ~/.claude-docker/.credentials.json:/home/codesensei/.claude/.credentials.json \
		-v ~/.claude-docker/.claude.json:/home/codesensei/.claude.json \
		live-courses \
		tmux new-session claude
