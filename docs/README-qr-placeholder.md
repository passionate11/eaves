# Put your payment QR codes here

Two files, dropped into this directory:

- `wechat.jpg` — WeChat
- `alipay.jpg` — Alipay

## Generating them

**WeChat:** Me → Services (服务) → Receive Money (收款) → Save Image (保存收款码).

**Alipay:** Home → Receive Money (收钱) → Save Image (保存图片).

Use the dedicated **receive-money code** (收款码), not the QR from your personal
profile page. The personal QR is a friend-request link: anyone who scans it can
add you, and it is tied to your account in a way the receive-money code is not.

## Before you commit them

These images end up in a public repository, indexed by search engines, and
present in the git history forever — removing a file in a later commit does not
remove it from the history.

So, worth a look before `git add`:

- **Crop out your name and avatar.** Both payment apps stamp them onto the
  saved image by default. The code works without them.
- **Turn off the fixed amount** if you set one — a "¥50" label on a donation
  code reads as a price tag.
- Consider whether you want the account tied to this to be your main one.

Once you have both files here, delete this README — `docs/DONATE.md` already
references the images directly.
