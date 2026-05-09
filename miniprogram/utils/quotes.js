const quotes = require('../data/quotes.js');

function pickQuote(currentContent) {
  if (!quotes.length) return null;
  if (quotes.length === 1) return quotes[0];

  let picked = quotes[Math.floor(Math.random() * quotes.length)];
  while (picked.content === currentContent) {
    picked = quotes[Math.floor(Math.random() * quotes.length)];
  }
  return picked;
}

module.exports = {
  pickQuote,
};
