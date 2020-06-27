FROM debian:buster-20200607

RUN apt update && \
	apt install -y curl && \
	curl -LO https://storage.googleapis.com/kubernetes-release/release/`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`/bin/linux/amd64/kubectl && \
	chmod +x ./kubectl && \
	mv ./kubectl /usr/local/bin/kubectl && \
	apt install -y jq && \
	mkdir /app

COPY script.sh /app/script.sh

WORKDIR /app

CMD ["bash", "script.sh"]