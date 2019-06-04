#!/bin/bash

if [[ -z $EMAIL || -z $DOMAINS || -z $SECRET ]]; then
	echo "EMAIL, DOMAINS, SECERT env vars required"
	env
	exit 1
fi

NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)

cd $HOME

echo "Listen python"
python -m SimpleHTTPServer 80 &
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

case $CODE in
409)
	echo "Secret already exist"
	RESP2=`curl -v --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" -k -v -XPATCH  -H "Accept: application/json, */*" -H "Content-Type: application/strategic-merge-patch+json" -d @/secret-patch.json https://kubernetes.default/api/v1/namespaces/${NAMESPACE}/secrets/${SECRET}`
	CODE2=`echo $RESP2 | jq -r '.code'`
	case $CODE2 in
	200)
		echo "Secret Updated"
		exit 0
		;;
	*)
		echo "Failed to update secret"
		echo "Unknown Error:"
		echo $RESP2
		exit 1
		;;
	;;
*)
	case $KIND in
	"Secret")
		echo "Secret Created"
		exit 0
		;;
	*)
		echo "Failed to create secret"
		echo "Unknown Error:"
		echo $RESP
		exit 1
		;;
	;;
