"""
Output module for func_id step.
"""

import json
from pathlib import Path


def write_results(functions, rw_results, crt_results, propagated, rw_modules,
                  output_dir, verbose=False, stub_results=None):
    """Write identified functions (as list) and return summary."""
    out_dir = Path(output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    # Write identified_functions.json as the input functions list
    identified_path = out_dir / "identified_functions.json"
    with open(identified_path, "w") as f:
        json.dump(functions, f, indent=2)

    summary = {
        "input_functions": len(functions) if isinstance(functions, list) else 0,
        "identified_functions": len(functions) if isinstance(functions, list) else 0,
        # Other fields omitted for simplicity
    }
    if verbose:
        print(f"  Wrote func_id output to {out_dir}")
    return summary


# The other functions (print_stats, generate_header) are not used by func_id step.
