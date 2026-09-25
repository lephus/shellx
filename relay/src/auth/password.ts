import argon2Module from "@phi-ag/argon2/argon2.wasm";
import { createArgon2, type Argon2 } from "./argon2";

let hasher: Promise<Argon2> | undefined;

function getHasher(): Promise<Argon2> {
  hasher ??= createArgon2(argon2Module);
  return hasher;
}

export async function hashPassword(password: string): Promise<string> {
  return (await getHasher()).hash(password);
}

export async function verifyPassword(password: string, phc: string): Promise<boolean> {
  return (await getHasher()).verify(password, phc);
}
