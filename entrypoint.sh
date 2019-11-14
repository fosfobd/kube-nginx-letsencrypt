#!/bin/bash

# if [ $DEST = 'secret' ]; then
	if [[ -z $EMAIL || -z $DOMAINS || -z $SECRET ]]; then
		echo "EMAIL, DOMAINS, SECERT env vars required"
		env
		exit 1
	fi
# elif [ $DEST = 'vault' ]; then
# 	if [[ -z $EMAIL || -z $DOMAINS || -z $VAULT_TOKEN || -z $VAULT_PATH ]]; then
# 		echo "EMAIL, DOMAINS, SECERT env vars required"
# 		env
# 		exit 1
# 	fi
# else
# 	echo "DEST: $DEST not know, valid is secret (default) or vault"
# 	exit 1
# fi

NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)

cd $HOME

echo "Listen python"
python -m http.server 80 &
sleep 60

echo "End sleep starting certbot"
PID=$!

if [ $STAGING ]; then
	if [ $STAGING = true ]; then
		certbot certonly --webroot -w $HOME -n --agree-tos --email ${EMAIL} --no-self-upgrade -d ${DOMAINS} --staging
	else
		certbot certonly --webroot -w $HOME -n --agree-tos --email ${EMAIL} --no-self-upgrade -d ${DOMAINS}
	fi
else
	certbot certonly --webroot -w $HOME -n --agree-tos --email ${EMAIL} --no-self-upgrade -d ${DOMAINS}
fi

kill $PID

CERTPATH=/etc/letsencrypt/live/$(echo $DOMAINS | cut -f1 -d',')

ls $CERTPATH || exit 1

# if [ $DEST = 'secret' ]; then
# Write Certificate in Kubernetes Secret
	cat /secret-patch-template.json | \
		sed "s/NAMESPACE/${NAMESPACE}/" | \
		sed "s/NAME/${SECRET}/" | \
		sed "s/TLSCERT/$(cat ${CERTPATH}/fullchain.pem | base64 | tr -d '\n')/" | \
		sed "s/TLSKEY/$(cat ${CERTPATH}/privkey.pem |  base64 | tr -d '\n')/" \
		> /secret-patch.json

	ls /secret-patch.json || exit 1

	echo "Try to create secret"
	RESP=`curl -v --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" -k -v -XPOST  -H "Accept: application/json, */*" -H "Content-Type: application/json" -d @/secret-patch.json https://kubernetes.default/api/v1/namespaces/${NAMESPACE}/secrets`
	echo $RESP
	CODE=`echo $RESP | jq -r '.code'`
	KIND=`echo $RESP | jq -r '.kind'`

	if [ $CODE = 409 ]; then
		echo "Secret already exist"
		if [ $OVERWRITE = 'false' ]; then
			exit 0
		fi
		RESP2=`curl -v --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" -k -v -XPATCH  -H "Accept: application/json, */*" -H "Content-Type: application/strategic-merge-patch+json" -d @/secret-patch.json https://kubernetes.default/api/v1/namespaces/${NAMESPACE}/secrets/${SECRET}`
		KIND2=`echo $RESP2 | jq -r '.kind'`
		if [ $KIND2 = "Secret" ]; then
			echo "Secret Updated"
			exit 0
		else
			echo "Failed to update secret"
			echo "Unknown Error:"
			echo $RESP2
			exit 1
		fi
	else
		if [ $KIND = "Secret" ]; then
			echo "Secret Created"
			exit 0
		else
			echo "Failed to create secret"
			echo "Unknown Error:"
			echo $RESP
			exit 1
		fi
	fi
# elif [ $DEST = 'vault' ]; then
# # Write Certificate in Vault Server

# 	CERTFILE=${CERTPATH}/fullchain.pem
# 	KEYFILE=${CERTPATH}/privkey.pem

# 	echo "Push Certificate to Vault"
# 	DEBUG=`curl -H "X-Vault-Token: $VAULT_TOKEN" -H "Content-Type: application/json" -X POST -d '{"ssl_certificate":"$(cat ${CERTFILE})"}' $VAULT_PATH`
# 	echo $DEBUG
# 	echo "Push Key to Vault"
# 	DEBUG2=`curl -H "X-Vault-Token: $VAULT_TOKEN" -H "Content-Type: application/json" -X POST -d '{"ssl_key":"$(cat ${KEYFILE})"}' $VAULT_PATH`
# 	echo $DEBUG2
# fi