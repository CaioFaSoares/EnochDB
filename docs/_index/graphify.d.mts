// Types only for what `.omp/hooks/pre/graphify.ts` imports. The contract lives in graphify.mjs.
export interface EstadoGrafo {
  ativo: boolean;
  existe?: boolean;
  atual?: boolean;
  nos?: number | null;
  commit?: string | null;
  head?: string | null;
}

export function ativo(): boolean;
export function estado(): EstadoGrafo;
export function resumo(e?: EstadoGrafo): string;
