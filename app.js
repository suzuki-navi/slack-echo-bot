const { App, AwsLambdaReceiver } = require('@slack/bolt');

const awsLambdaReceiver = new AwsLambdaReceiver({
  signingSecret: process.env.SLACK_SIGNING_SECRET
});
const app = new App({
  token: process.env.SLACK_BOT_TOKEN,
  receiver: awsLambdaReceiver
});

app.event('app_mention', async ({ event, context, client, say }) => {
  // メンションのイベントを受信したときに実行されるコード
  try {
    console.log(event);
    const { channel, event_ts, text } = event;

    // check if text starts with a mention '<@...>' using regex, and then remove it from text
    const textWithoutMention = text.replace(/^<@(.+?)>/, '').trim();

    await say({
      channel,
      thread_ts: event_ts, // 返信先スレッドを識別するための文字列
      text: "Hello! :wave: \n> " + textWithoutMention,
    });
  } catch (error) {
    console.error(error);
  }
});

exports.lambda_handler = async (event, context, callback) => {
  console.log(event);
  const handler = await awsLambdaReceiver.start();
  return handler(event, context, callback);
};
