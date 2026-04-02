from dataclasses import dataclass, field
from typing import Optional
import csv
import io

# ── Data Classes ──────────────────────────────────────────────────────────────

@dataclass
class FormulationInput:
    total_mass_g: float = 5000.0
    nonPU_percent: float = 89.31
    nco_oh_ratio: float = 0.85
    oh_meq_per_g: float = 0.75
    nco_meq_per_g: float = 8.9
    oh_sources_count: int = 2          # 1 or 2
    oh2_meq_per_g: Optional[float] = 0.32
    butacene_percent_input: Optional[float] = 1.0

    def validate(self):
        assert self.total_mass_g > 0, "Total mass must be > 0"
        assert 0 <= self.nonPU_percent <= 100, "Non-PU % must be between 0 and 100"
        assert self.nco_oh_ratio > 0, "NCO/OH ratio must be > 0"
        assert self.oh_meq_per_g > 0, "OH meq/g must be > 0"
        assert self.nco_meq_per_g > 0, "NCO meq/g must be > 0"
        assert self.oh_sources_count in (1, 2), "OH sources count must be 1 or 2"
        if self.oh_sources_count == 2:
            assert self.oh2_meq_per_g is not None and self.oh2_meq_per_g > 0, \
                "2nd OH meq/g is required and must be > 0 when using 2 OH sources"
            assert self.butacene_percent_input is not None, \
                "Butacene % is required when using 2 OH sources"
            pu_percent = 100 - self.nonPU_percent
            assert self.butacene_percent_input <= pu_percent, \
                f"Butacene % ({self.butacene_percent_input}) cannot exceed PU % ({pu_percent:.4f})"


@dataclass
class ComponentResult:
    name: str
    mass_percent: float
    mass_g: float


@dataclass
class FormulationSummary:
    total_mass_g: float
    nonPU_percent: float
    pu_percent: float
    oh_sources_count: int
    ew_oh: float
    ew_nco: float
    ew_oh2: Optional[float] = None
    x_factor: Optional[float] = None
    consistency_ok: bool = True
    consistency_diff: float = 0.0


@dataclass
class FormulationResult:
    summary: FormulationSummary
    components: list[ComponentResult] = field(default_factory=list)


# ── Core Calculation ──────────────────────────────────────────────────────────

def calculate_formulation(inp: FormulationInput) -> FormulationResult:
    inp.validate()

    # 1. PU system percent
    pu_percent = 100.0 - inp.nonPU_percent

    # 2. Equivalent weights
    EW_OH  = 1000.0 / inp.oh_meq_per_g
    EW_NCO = (1000.0 / inp.nco_meq_per_g) * inp.nco_oh_ratio

    htpb_percent    = 0.0
    curing_percent  = 0.0
    butacene_percent = 0.0
    ew_oh2: Optional[float] = None
    x_factor: Optional[float] = None

    # ── Case A: Single OH Source ──────────────────────────────────────────────
    if inp.oh_sources_count == 1:
        EW_total       = EW_OH + EW_NCO
        htpb_percent   = (EW_OH  / EW_total) * pu_percent
        curing_percent = (EW_NCO / EW_total) * pu_percent

    # ── Case B: Dual OH Source ────────────────────────────────────────────────
    else:
        oh2_meq         = inp.oh2_meq_per_g          # type: ignore[arg-type]
        butacene_p      = inp.butacene_percent_input  # type: ignore[arg-type]

        ew_oh2           = 1000.0 / oh2_meq
        butacene_percent = butacene_p

        B   = butacene_percent / 100.0
        PU  = pu_percent / 100.0

        numerator   = B * (EW_OH + EW_NCO)
        denominator = (ew_oh2 * (PU - B)) + (B * EW_OH)

        x = numerator / denominator
        x = max(0.0, min(1.0, x))   # numerical safety clamp
        x_factor = x

        eq_htpb       = 1.0 - x
        remaining_pu  = pu_percent - butacene_percent
        denom2        = (eq_htpb * EW_OH) + EW_NCO

        htpb_percent   = ((eq_htpb * EW_OH) / denom2) * remaining_pu
        curing_percent = remaining_pu - htpb_percent

    # 3. Build components list
    components: list[ComponentResult] = [
        ComponentResult(
            name="HTPB (Binder)",
            mass_percent=htpb_percent,
            mass_g=(htpb_percent / 100.0) * inp.total_mass_g,
        ),
        ComponentResult(
            name="Curing Agent",
            mass_percent=curing_percent,
            mass_g=(curing_percent / 100.0) * inp.total_mass_g,
        ),
    ]

    if inp.oh_sources_count == 2:
        components.insert(1, ComponentResult(
            name="2nd OH Source (Butacene)",
            mass_percent=butacene_percent,
            mass_g=(butacene_percent / 100.0) * inp.total_mass_g,
        ))

    # 4. Consistency check
    calc_sum       = sum(c.mass_percent for c in components)
    diff           = abs(calc_sum - pu_percent)
    consistency_ok = diff < 0.001

    summary = FormulationSummary(
        total_mass_g      = inp.total_mass_g,
        nonPU_percent     = inp.nonPU_percent,
        pu_percent        = pu_percent,
        oh_sources_count  = inp.oh_sources_count,
        ew_oh             = EW_OH,
        ew_nco            = EW_NCO,
        ew_oh2            = ew_oh2,
        x_factor          = x_factor,
        consistency_ok    = consistency_ok,
        consistency_diff  = diff,
    )

    return FormulationResult(summary=summary, components=components)


# ── Output Helpers ────────────────────────────────────────────────────────────

def print_results(result: FormulationResult) -> None:
    s = result.summary
    print("=" * 55)
    print("  POLYURETHANE FORMULATION RESULTS")
    print("=" * 55)
    print(f"  Total Mass         : {s.total_mass_g:>10.2f} g")
    print(f"  Non-PU (Fillers)   : {s.nonPU_percent:>10.4f} %")
    print(f"  PU System          : {s.pu_percent:>10.4f} %")
    print(f"  OH Sources         : {s.oh_sources_count}")
    print(f"  EW (OH)            : {s.ew_oh:>10.4f} g/eq")
    print(f"  EW (NCO)           : {s.ew_nco:>10.4f} g/eq")
    if s.ew_oh2 is not None:
        print(f"  EW (2nd OH)        : {s.ew_oh2:>10.4f} g/eq")
    if s.x_factor is not None:
        print(f"  X-Factor           : {s.x_factor:>10.6f}")
    balance = "OK (verified)" if s.consistency_ok else f"WARNING  Δ={s.consistency_diff:.5f}%"
    print(f"  Mass Balance       : {balance}")
    print("-" * 55)
    print(f"  {'Component':<28} {'Mass %':>8}  {'Mass (g)':>10}")
    print("-" * 55)
    for c in result.components:
        print(f"  {c.name:<28} {c.mass_percent:>7.4f}%  {c.mass_g:>10.2f}")
    filler_g = (s.nonPU_percent / 100.0) * s.total_mass_g
    print(f"  {'Fillers / Non-PU':<28} {s.nonPU_percent:>7.4f}%  {filler_g:>10.2f}")
    print("-" * 55)
    print(f"  {'TOTAL BATCH':<28} {'100.0000%':>8}  {s.total_mass_g:>10.2f}")
    print("=" * 55)


def to_csv_string(result: FormulationResult) -> str:
    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow(["Component", "Mass %", "Mass (g)"])
    for c in result.components:
        writer.writerow([c.name, f"{c.mass_percent:.4f}", f"{c.mass_g:.4f}"])
    s = result.summary
    filler_g = (s.nonPU_percent / 100.0) * s.total_mass_g
    writer.writerow(["Fillers / Non-PU", f"{s.nonPU_percent:.4f}", f"{filler_g:.4f}"])
    writer.writerow(["TOTAL BATCH", "100.0000", f"{s.total_mass_g:.4f}"])
    return buf.getvalue()


# ── Entry Point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    # --- Edit these parameters as needed ---
    inp = FormulationInput(
        total_mass_g          = 5000,
        nonPU_percent         = 89.31,
        nco_oh_ratio          = 0.85,
        oh_meq_per_g          = 0.75,
        nco_meq_per_g         = 8.9,
        oh_sources_count      = 2,
        oh2_meq_per_g         = 0.32,
        butacene_percent_input= 1.0,
    )

    result = calculate_formulation(inp)
    print_results(result)

    # Optionally save to CSV:
    # with open("formulation_results.csv", "w", newline="") as f:
    #     f.write(to_csv_string(result))
    # print("\nSaved to formulation_results.csv")
