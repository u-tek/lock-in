# 0004: One APNs provider token for every isolate

Status: **implemented in M3** (the singleton Durable Object option), awaiting the owner's sign-off.

Affects: M0 (how to read one possible spike result) and M3 (the push fan-out from `Room` Durable
Objects).

## Context

SPEC.md §4.2: *"Cache the JWT and refresh it every 20–50 minutes."*

`server/src/apns.ts` does this per isolate. Each isolate keeps one `ApnsClient`, which signs a
provider token on first use and signs again once it's 40 minutes old. Its comment says Apple rejects
a token *"refreshed more than every 20 minutes"*.

## Finding

Apple's rule is per **connection**, not per sender: *"APNs report an error if you use a new token more
than once every 20 minutes on the same connection"*. The error is `429 TooManyProviderTokenUpdates`,
not a 403
([Establishing a token-based connection to APNs](https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns),
[Handling notification responses from APNs](https://developer.apple.com/documentation/usernotifications/handling-notification-responses-from-apns)).

On Cloudflare, three facts combine:

- Requests to the Worker land on many isolates, and in M3 every `Room` Durable Object may run in its
  own. Each one signs its own token.
- Web Crypto's ECDSA signatures are randomised, so two isolates signing the same header and claims
  in the same second still produce two different tokens.
- Our code doesn't own the connection to APNs. Cloudflare's proxy does: it's what speaks HTTP/2 to
  APNs on the Worker's behalf
  ([cloudflare/workerd#4841](https://github.com/cloudflare/workerd/issues/4841)). Whether two isolates'
  requests share one connection isn't documented, so we can't rule it out.

At least one open-source Worker sending Live Activity pushes hit exactly this. It has every isolate
round `iat` down to a shared window and sign deterministically, *"so APNs never answers
TooManyProviderTokenUpdates"* ([frink#139](https://github.com/benord-labs/frink/pull/139)).

Confidence: medium. The rule is Apple's; that it bites on Cloudflare is inferred from the above, not
observed by us.

## Proposal

1. **SPEC.md §4.2:** replace *"Cache the JWT and refresh it every 20–50 minutes"* with *"Every
   isolate (the Worker and each Room) presents the same provider token, which changes at most once
   every 20 minutes and at least once every 60. On `429 TooManyProviderTokenUpdates`, retry later
   with the same token; sign again only on `403 ExpiredProviderToken`."*
2. **Implementation, M3** (sooner if the spike sees this 429): make the token identical across
   isolates by construction.
   - Set `iat` to the start of a fixed window: `floor(now / 1800) * 1800`. A token is then never more
     than 30 minutes old and changes every 30 minutes.
   - Sign it with deterministic ECDSA (RFC 6979; for example `@noble/curves`' P-256, which is
     deterministic by default) instead of Web Crypto's randomised signing.

   Every isolate then computes the same string in the same window, with no coordination. The
   alternative is a singleton Durable Object that mints and hands out the token. That works, but it
   adds a hop and a single point of failure to every push batch.
3. **`server/src/apns.ts`:** correct the comment on `PROVIDER_TOKEN_REFRESH_SECONDS` to say the
   20-minute rule is per connection. The current behaviour on a 429 is already right: return it,
   don't re-sign.

During the spike, a `429 TooManyProviderTokenUpdates` means the Worker **did** reach APNs over
HTTP/2. It's a reason to do step 2 early, not evidence against Workers (`docs/spikes/apns-worker.md`).
