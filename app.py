import streamlit as st
from dataclasses import dataclass, field
from typing import Optional

# ---------------- DATA ----------------
@dataclass
class FormulationInput:
    total_mass_g: float
    nonPU_percent: float
    nco_oh_ratio: float
    oh_meq_per_g: float
    nco_meq_per_g: float
    oh_sources_count: int
    oh2_meq_per_g: Optional[float]
    butacene_percent_input: Optional[float]

# ---------------- CALCULATION ----------------
def calculate(inp):
    pu_percent = 100 - inp.nonPU_percent

    EW_OH  = 1000 / inp.oh_meq_per_g
    EW_NCO = (1000 / inp.nco_meq_per_g) * inp.nco_oh_ratio

    if inp.oh_sources_count == 1:
        EW_total = EW_OH + EW_NCO
        htpb = (EW_OH / EW_total) * pu_percent
        curing = (EW_NCO / EW_total) * pu_percent
        butacene = 0
    else:
        ew_oh2 = 1000 / inp.oh2_meq_per_g
        B = inp.butacene_percent_input / 100
        PU = pu_percent / 100

        x = (B * (EW_OH + EW_NCO)) / ((ew_oh2 * (PU - B)) + (B * EW_OH))
        x = max(0, min(1, x))

        remaining = pu_percent - inp.butacene_percent_input

        htpb = remaining * 0.6
        curing = remaining - htpb
        butacene = inp.butacene_percent_input

    return htpb, curing, butacene, pu_percent

# ---------------- UI ----------------
st.title("Polyurethane Formulation Calculator")

total_mass = st.number_input("Total Mass (g)", value=5000.0)
nonPU = st.number_input("Non-PU %", value=89.31)
ratio = st.number_input("NCO/OH Ratio", value=0.85)
oh = st.number_input("OH meq/g", value=0.75)
nco = st.number_input("NCO meq/g", value=8.9)

sources = st.selectbox("OH Sources", [1, 2])

oh2 = None
butacene = None

if sources == 2:
    oh2 = st.number_input("2nd OH meq/g", value=0.32)
    butacene = st.number_input("Butacene %", value=1.0)

if st.button("Calculate"):
    inp = FormulationInput(
        total_mass, nonPU, ratio, oh, nco, sources, oh2, butacene
    )

    htpb, curing, butacene_val, pu = calculate(inp)

    st.success("Results")

    st.write(f"PU System %: {pu:.4f}")
    st.write(f"HTPB %: {htpb:.4f}")
    st.write(f"Curing Agent %: {curing:.4f}")

    if sources == 2:
        st.write(f"Butacene %: {butacene_val:.4f}")
