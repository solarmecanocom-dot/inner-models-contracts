// Constructor arguments for PoolManager deployed at 0x3FC012583Ccec0B7f55708e193710b2f533F054e on Base mainnet
// constructor(address _nft, address _priceFeed, address _sequencerFeed, address _creator, uint8[] memory _tierAssignments)

const MODEL_TIERS = [0, 0, 1, 1, 1, 2, 3, 1, 2, 0, 1, 2, 2, 0, 1, 1, 1, 2, 3, 1, 0, 1, 0, 0];
const QUESTIONS_PER_MODEL = 11;

// 24 models x 11 questions = 264 tier assignments
const tierAssignments = [];
for (const tier of MODEL_TIERS) {
  for (let i = 0; i < QUESTIONS_PER_MODEL; i++) {
    tierAssignments.push(tier);
  }
}

module.exports = [
  "0xB032B7053138cedFB3d948Ab5Beeb42eA0549195",  // _nft
  "0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70",  // _priceFeed
  "0xBCF85224fC0756b9fA45AAb7d157a8263913fDa1",  // _sequencerFeed
  "0x36B68cE802E3b497c3385A34E709c323376c5837",  // _creator
  tierAssignments,                                  // _tierAssignments (264 uint8 values)
];
