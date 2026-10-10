const seo = require("./seo");

// Crawlers receive publisher content but never an advertising script.
// Ninja AdMax is mounted only by the human-facing Flutter timeline view.
module.exports = (req, res) =>
  seo(
    {
      ...req,
      query: {
        ...(req.query || {}),
        path: "/",
      },
    },
    res,
  );
