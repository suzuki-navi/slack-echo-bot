import os
import re
from slack_bolt import App
from slack_bolt.adapter.aws_lambda import SlackRequestHandler

app = App(
  token=os.environ.get("SLACK_BOT_TOKEN"),
  signing_secret=os.environ.get("SLACK_SIGNING_SECRET"),
  
  # これがない場合、app_metionに反応はできるけどsayする前にLambdaが終了してしまい、ボットが返信完了できない
  process_before_response=True,
)
receiver = SlackRequestHandler(app)

# メンションのイベントを受信したときに実行されるコード
@app.event("app_mention")
def onAppMention(event, say):
  print(event)

  # check if event["text"] starts with a mention '<@...>' using regex, and then remove it from text
  textWithoutMention = re.sub(r"^<@(.+?)>", "", event["text"]).strip()

  say(
    channel=event["channel"],
    thread_ts=event["event_ts"], # 返信先スレッドを識別するための文字列
    text="Hello! :wave: \n> " + textWithoutMention,
  )

def lambda_handler(event, context):
  return receiver.handle(event, context)
