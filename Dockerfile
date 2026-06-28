# helloworld container image
FROM alpine

COPY root-user airflow-setup

CMD [ "sleep", "3600" ]