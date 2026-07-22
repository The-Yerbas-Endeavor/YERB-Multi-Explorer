import mongoose from 'mongoose';

const blockSchema = new mongoose.Schema({
  hash: { type: String, required: true, unique: true, index: true },
  height: { type: Number, required: true, unique: true, index: true },
  previousBlockHash: { type: String, default: null, index: true },
  nextBlockHash: { type: String, default: null, index: true },
  confirmations: { type: Number, default: 0 },
  time: { type: Date, required: true, index: true },
  size: { type: Number, default: 0 },
  difficulty: { type: Number, default: 0 },
  transactionCount: { type: Number, default: 0 },
  raw: { type: mongoose.Schema.Types.Mixed, default: {} }
}, { timestamps: true, versionKey: false });

export const Block = mongoose.model('Block', blockSchema);
