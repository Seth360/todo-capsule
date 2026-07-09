# Todo Capsule Vercel Proxy

This folder is a minimal Vercel API proxy for Todo Capsule's built-in preset model.

The app calls:

```text
https://fuxc.team/api/summary
```

The Vercel Function reads the real model key from server-side environment variables, then calls an OpenAI-compatible `/chat/completions` endpoint. Do not put the real key in the macOS app or in this repository.

## Environment Variables

Set these in the Vercel project:

```text
AI_PROXY_API_KEY=your-real-model-key
AI_PROXY_APP_TOKEN=random-app-token-shared-with-release-builds
AI_PROXY_BASE_URL=https://api.openai.com/v1
AI_PROXY_MODEL=gpt-4.1-mini
AI_PROXY_MAX_PROMPT_CHARS=12000
```

Only `AI_PROXY_API_KEY` is required. `AI_PROXY_APP_TOKEN` is strongly recommended for public deployments. The other variables have defaults.

Release builds should send the same token in `X-Todo-Capsule-Token`. Keep the token out of Git and inject it during packaging.

`AI_PROXY_BASE_URL` can be a provider root, a `/v1` root, or a full `/chat/completions` URL.

For other OpenAI-compatible providers, change `AI_PROXY_BASE_URL` and `AI_PROXY_MODEL`, for example:

```text
AI_PROXY_BASE_URL=https://api.deepseek.com/v1
AI_PROXY_MODEL=deepseek-chat
```

## Deploy

If your Vercel project already has a site, copy `api/summary.ts` into that project's root `api/` folder and redeploy.

If you deploy this folder as a separate Vercel project, set the project root directory to `vercel-proxy`.

## Safety Notes

This proxy hides the model key, but the endpoint can still be abused if it is public. Use a separate model-provider key with a strict budget limit and usage alerts. Add real rate limiting before sending the app to a large audience.
