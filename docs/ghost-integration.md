# Ghost subscriber integration

This deployment has a server-specific integration with the Contraption newsletter,
using `SubscribeToContraptionGhostJob`. It is not a general Ghost connection for
Postcard customers; the destination remains the existing Contraption service.

The upgrade backfills `sync_to_ghost` for the existing `philipithomas` account, which
the previous controller enabled by slug. All other accounts, including new
accounts, default to disabled. Renaming an enabled account preserves its setting.
The migration does not enqueue jobs or transfer existing subscribers.

An administrator can enable or disable the integration on **Edit your page →
Administrator integration**, for their own account only. The form names the
destination explicitly. Ordinary authors cannot change this setting, including
through direct requests or the general page editor. Administrators cannot enable
it for another author's account. A legacy enabled account that is not an
administrator retains its existing behavior; its operator can disable it through
the Rails console if necessary.

Only successful subscription verification that changes `verified_at` queues a
Ghost request. Reopening an already verified link does not queue another request.
Expired/invalid links and old links after unsubscription cannot reactivate a
subscription. Disabling the integration stops future verification enqueues; it
does not remove members from Ghost or cancel jobs that have already been queued.

Connecting a different author's Ghost newsletter needs a separate design with an
account-specific destination, credentials and explicit ownership/consent. Do not
enable this fixed destination as a substitute. Durable delivery/retry deduplication
is also separate from verification-link replay protection.
