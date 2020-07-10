nix-shell /nixenv/nixuser/dev.nix --run "cd /home/nixuser; mpirun -np 4 --allow-run-as-root xhpl HPL.dat"
