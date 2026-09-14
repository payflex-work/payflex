module.exports = {
  moduleFileExtensions: ['js', 'json', 'ts'],
  rootDir: 'src',
  testRegex: '.*\\.spec\\.ts$',
  transform: {
    '^.+\\.(t|j)s$': 'ts-jest',
    // @stellar/stellar-sdk (and its deps) ship untranspiled ESM; babel
    // must compile them or every spec importing the SDK fails to run.
    '^.+\\.m?js$': ['babel-jest', { presets: ['@babel/preset-env'] }],
  },
  transformIgnorePatterns: ['node_modules/(?!(?:@stellar|stellar-base|js-xdr|uint8array-extras|@exodus|@noble)/)'],
  collectCoverageFrom: ['**/*.(t|j)s'],
  testEnvironment: 'node',
};
