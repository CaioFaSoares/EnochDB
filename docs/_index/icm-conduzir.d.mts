// Types only for what the hook `.omp/hooks/pre/icm-jev.ts` imports. The contract lives in icm-conduzir.mjs.
import type { Fatos } from "./jev-gate.mjs";

export function sprints(): string[];
export function etapaAtual(fatos: Fatos): { nome: string; status: string | null } | null;
