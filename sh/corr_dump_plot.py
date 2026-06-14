import numpy as np
import matplotlib.pyplot as plt

# --------------------------------------------------------------------
# Load corr_dump.txt
# Expected columns (as written by tb_tracking_channel):
#   0: dump_count
#   1: i_early
#   2: q_early
#   3: i_prompt
#   4: q_prompt
#   5: i_late
#   6: q_late
#   7: ie_pow
#   8: ip_pow
#   9: il_pow
# --------------------------------------------------------------------
d0 = np.loadtxt("corr_dump.txt")

t0 = d0[:, 0] # dump_count

# Powers 
p0 = d0[:, 8]  # ip_pow
e0 = d0[:, 7]  # ie_pow
l0 = d0[:, 9]  # il_pow

# Figure 1: Power vs dump index
plt.figure(1)
plt.plot(t0, p0, label="Prompt power")
plt.plot(t0, e0, label="Early power")
plt.plot(t0, l0, label="Late power")
plt.grid(True)
plt.xlabel("Dump index")
plt.ylabel("Power (I^2 + Q^2)")
plt.legend()
plt.tight_layout()

# Figure 2: I/Q scatter for prompt + average-radius circle
i0 = d0[:, 3]  # i_prompt
q0 = d0[:, 4]  # q_prompt

r = np.mean(np.sqrt(i0**2 + q0**2))
th = np.arange(0, 361, 5)  # 0:5:360
ic = r * np.cos(np.deg2rad(th))
qc = r * np.sin(np.deg2rad(th))

plt.figure(2)
plt.plot(i0, q0, ".", label="Prompt I/Q")
plt.plot(ic, qc, "-", label=f"Mean radius circle (r={r:.2f})")
plt.grid(True)
plt.axis("equal")
plt.xlabel("I_prompt")
plt.ylabel("Q_prompt")
plt.legend()
plt.tight_layout()

# Figure 3: I/Q prompt vs dump index

plt.figure(3)
plt.plot(t0, i0, label="I Prompt")
plt.plot(t0, q0, label="Q Prompt")
plt.grid(True)
plt.xlabel("Dump index")
plt.ylabel("I/Q_prompt")
plt.legend()
plt.tight_layout()

plt.show()
