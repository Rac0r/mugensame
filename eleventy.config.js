import { EleventyHtmlBasePlugin } from "@11ty/eleventy";

export default function (eleventyConfig) {
    eleventyConfig.addPlugin(EleventyHtmlBasePlugin);
    return {
        pathPrefix: "/repo-name/",
        dir: { input: "src", output: "_site" }
    };
}