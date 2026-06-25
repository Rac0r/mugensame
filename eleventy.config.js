export default function (eleventyConfig) {
    // Static assets
    eleventyConfig.addPassthroughCopy("src/css");
    eleventyConfig.addPassthroughCopy("src/js");

    // --- Filters ---
    eleventyConfig.addFilter("readableDate", (dateObj) => {
        return new Date(dateObj).toLocaleDateString("de-DE", {
            day: "numeric",
            month: "short",
            year: "numeric",
        });
    });

    eleventyConfig.addFilter("htmlDateString", (dateObj) => {
        return new Date(dateObj).toISOString().split("T")[0];
    });

    // No external dependency needed for a basic slug
    eleventyConfig.addFilter("slugify", (str) =>
        String(str)
            .toLowerCase()
            .trim()
            .replace(/[^a-z0-9]+/g, "-")
            .replace(/(^-|-$)+/g, "")
    );

    eleventyConfig.addFilter("limit", (arr, limit) => (arr || []).slice(0, limit));

    // --- Collections ---
    // All blog posts, newest first
    eleventyConfig.addCollection("posts", (collectionApi) => {
        return collectionApi
            .getFilteredByGlob("src/posts/*.md")
            .sort((a, b) => b.date - a.date);
    });

    // Every unique tag used across posts, excluding internal/structural tags
  eleventyConfig.addCollection("tagList", (collectionApi) => {
    const tagSet = new Set();
    collectionApi.getAll().forEach((item) => {
      (item.data.tags || []).forEach((tag) => {
        if (!["posts", "all", "nav"].includes(tag)) tagSet.add(tag);
      });
    });
    return [...tagSet].sort();
  });
 
  return {
    // Change this to match your repo name (e.g. "/blog/"), or remove entirely
    // if you're deploying to a custom domain or a <username>.github.io repo.
    pathPrefix: "/mugensame/",
    dir: {
      input: "src",
      includes: "_includes",
      data: "_data",
      output: "_site",
    },
  };
}