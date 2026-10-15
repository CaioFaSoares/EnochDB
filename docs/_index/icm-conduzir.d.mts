// Tipos só do que o hook `.omp/hooks/pre/icm-jev.ts` importa. O contrato vive em icm-conduzir.mjs.
import type { Fatos } from "./jev-gate.mjs";

export function sprints(): string[];
export function etapaAtual(fatos: Fatos): { nome: string; status: string | null } | null;
