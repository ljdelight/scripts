
run:
	docker-compose up -d

setup:
	sudo mkdir -p /opt/automation
	sudo chown -R $(shell whoami):$(shell whoami) /opt/automation

	mkdir -p /opt/automation/gitlab/{config,logs,data}
	mkdir -p /opt/automation/jenkins-master/
	chmod -R 775 /opt/automation
