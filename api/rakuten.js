// Legacy endpoint intentionally retired after migration to NDL/openBD.
// Keep a 410 response for stale clients; never contact Rakuten Web Service.
function createHandler() {
  return async (req, res) => {
    res.setHeader("Cache-Control", "no-store");
    return res.status(410).json({
      error: "catalog_migrated",
      message: "Rakuten Books API has been retired. Update the app.",
    });
  };
}
const handler = createHandler();
handler.createHandler = createHandler;
module.exports = handler;
