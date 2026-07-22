import mongoose from 'mongoose';

const assetSchema = new mongoose.Schema({
  name: { type: String, required: true, unique: true, index: true },
  amount: { type: mongoose.Schema.Types.Decimal128, default: 0 },
  units: { type: Number, default: 0 },
  reissuable: { type: Boolean, default: false },
  hasIpfs: { type: Boolean, default: false },
  ipfsHash: { type: String, default: null },
  verifierString: { type: String, default: null },
  restricted: { type: Boolean, default: false },
  holderCount: { type: Number, default: 0 },
  transactionCount: { type: Number, default: 0 },
  issueTxid: { type: String, default: null, index: true },
  issueHeight: { type: Number, default: null, index: true },
  raw: { type: mongoose.Schema.Types.Mixed, default: {} }
}, { timestamps: true, versionKey: false });

export const Asset = mongoose.model('Asset', assetSchema);
