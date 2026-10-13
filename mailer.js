import { google } from 'googleapis';
// Gmail API over HTTPS (works on Render free tier; SMTP ports may be blocked there).
const auth = new google.auth.OAuth2(process.env.GMAIL_CLIENT_ID, process.env.GMAIL_CLIENT_SECRET);
auth.setCredentials({ refresh_token: process.env.GMAIL_REFRESH_TOKEN });
const gmail = google.gmail({ version: 'v1', auth });
export async function sendMail(to, subject, html) {
  const raw = Buffer.from([
    `From: Grand Aurum <${process.env.GMAIL_SENDER}>`, `To: ${to}`,
    `Subject: =?UTF-8?B?${Buffer.from(subject).toString('base64')}?=`,
    'MIME-Version: 1.0', 'Content-Type: text/html; charset=UTF-8', '', html].join('\r\n')).toString('base64url');
  await gmail.users.messages.send({ userId: 'me', requestBody: { raw } });
}
