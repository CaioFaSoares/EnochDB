// Tipos só do que o hook `.omp/hooks/pre/icm-jev.ts` importa. O contrato vive em jev-gate.mjs.
export const RAIZ: string;

export interface Guarda {
  proteger: string[];
  proteger_recibos: string;
  ficha_de_etapa: string;
  status_que_pede_dono: string;
}

export interface Config {
  conducao: { guarda: Guarda };
}

export interface Frescor {
  estado: "sem_gate" | "sem_artefato" | "sem_recibo" | "desatualizado" | "atual";
  etapa: string;
  gate?: string;
  recibo?: string;
  veredito?: string;
  mudados?: string[];
  falhas?: string[];
}

export interface Fatos {
  etapas: { nome: string; status: string | null }[];
}

export function carregarConfig(): Config;
export function frescor(sprint: string, etapa: string): Frescor;
export function fatosDoSprint(sprint: string): Fatos;
