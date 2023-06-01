FROM public.ecr.aws/lambda/python:3.10

COPY requirements.txt app.py  ${LAMBDA_TASK_ROOT}/

RUN pip3 install -r requirements.txt

CMD [ "app.lambda_handler" ]
