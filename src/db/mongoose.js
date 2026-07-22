import mongoose from 'mongoose';
import { config } from '../config/index.js';

export async function connectDatabase() {
  mongoose.set('strictQuery', true);
  await mongoose.connect(config.mongodbUri, {
    serverSelectionTimeoutMS: 10000
  });
  return mongoose.connection;
}

export async function disconnectDatabase() {
  await mongoose.disconnect();
}
