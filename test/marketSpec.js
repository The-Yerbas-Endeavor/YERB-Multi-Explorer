describe('market modules', function() {
  const exbitron = require('../lib/markets/exbitron');
  const nestex = require('../lib/markets/nestex');

  function verifyMarketModule(market) {
    expect(market).toBeDefined();
    expect(typeof market.market_name).toBe('string');
    expect(typeof market.market_url_template).toBe('string');
    expect(typeof market.get_data).toBe('function');
  }

  it('loads the Exbitron market adapter', function() {
    verifyMarketModule(exbitron);
    expect(exbitron.market_name).toBe('Exbitron');
  });

  it('loads the Nestex market adapter', function() {
    verifyMarketModule(nestex);
    expect(nestex.market_name).toBe('NestEx');
  });
});
