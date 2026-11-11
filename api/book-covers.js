// Disabled: Google Books rights for a paid Sharemarium app have not been
// established. No outbound calls, no thumbnails or cached Google metadata.
// This endpoint deliberately stays as HTTP 410 so old clients cannot revive
// the unapproved integration. Re-enable only after written permissions.
function createHandler() {
  return async (req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    if (req.method !== 'GET') {
      res.setHeader('Allow', 'GET');
      return res.status(405).json({ error: 'method_not_allowed' });
    }
    return res.status(410).json({ error: 'provider_disabled_pending_rights' });
  };
}

const handler = createHandler();
handler.createHandler = createHandler;
module.exports = handler;
