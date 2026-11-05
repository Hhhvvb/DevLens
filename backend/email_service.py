import smtplib

from email.message import EmailMessage

class LocalEmailService:
    def send_verification_email(
        self,
        email: str,
        token: str,
    ) -> None:
        message = EmailMessage()

        message["From"] = "DevLens <no-reply@Devlens.local>"
        message["To"] = email
        message["Subject"] = "验证你的 DevLens 邮箱"

        message.set_content(
            "欢迎使用 DevLens！\n\n"
            "你的邮箱验证 token 是：\n\n"
            f"{token}\n\n"
            "请在 30 分钟内完成验证。\n"
            "如果不是你本人操作，请忽略这封邮件。"
        )

        with smtplib.SMTP(
            host="127.0.0.1",
            port=1025,
            timeout=10,
        ) as connection:
            connection.send_message(message)