{
  description = "A flake exposing Kaleido python package";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  } @ inputs:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
        # custom config
      };
      lib = nixpkgs.lib;
      python = pkgs.python39;
      pythonPackages = pkgs.python39Packages;
      pythonVersion = "3.9";
      kaleido = with pkgs;
        pythonPackages.buildPythonPackage rec {
          pname = "Kaleido";
          version = "0.2.1";
          src = fetchurl {
            url = "https://github.com/plotly/Kaleido/releases/download/v0.2.1/kaleido-0.2.1-py2.py3-none-manylinux1_x86_64.whl";
            sha256 = "sha256-qiHPG/HHj4+lCp99ReEAPDh709b+CnZ8+780S5W9w6g=";
          };

          format = "wheel";
          nativeBuildInputs = [
            makeWrapper
          ];
          buildInputs = [
            # needed to update shebang in .kaleido-wrapped
            bash
          ];

          postInstall = ''
            patchShebangs $out/lib/python${pythonVersion}/site-packages/kaleido/executable/kaleido

            wrapProgram $out/lib/python${pythonVersion}/site-packages/kaleido/executable/kaleido \
              --prefix LD_LIBRARY_PATH : "$out/lib/python${pythonVersion}/site-packages/kaleido/executable/lib" \
              --set FONTCONFIG_PATH "$out/lib/python${pythonVersion}/site-packages/kaleido/executable/etc/fonts" \
              --prefix XDG_DATA_HOME : "$out/lib/python${pythonVersion}/site-packages/kaleido/executable/xdg" \
              --unset LD_PRELOAD

            # let wrapped script find the real kaleido executable
            substituteInPlace $out/lib/python${pythonVersion}/site-packages/kaleido/executable/.kaleido-wrapped \
              --replace './bin/kaleido' $out/lib/python${pythonVersion}/site-packages/kaleido/executable/bin/kaleido
          '';
          preFixup = let
            libPath = lib.makeLibraryPath [
              nss
              nspr
              expat
              stdenv.cc.cc.lib # libstdc++.so.6
              # saneBackends # libsane.so.1
            ];
          in ''
            patchelf \
              --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
              --set-rpath "${libPath}" \
              $out/lib/python${pythonVersion}/site-packages/kaleido/executable/bin/kaleido
          '';

          checkInputs = [
            pythonPackages.plotly
            pythonPackages.pandas
            pythonPackages.packaging
          ];
          doCheck = true;
          checkPhase = ''
              # Test script
              cat > test_kaleido.py << EOF
            import os
            import tempfile
            import plotly.express as px

            def is_png(file_path):
                with open(file_path, 'rb') as f:
                    file_signature = f.read(8)
                    png_signature = b'\x89PNG\r\n\x1a\n'
                return file_signature == png_signature

            fig = px.scatter(px.data.iris(), x="sepal_length", y="sepal_width", color="species")

            # Create a temporary file
            with tempfile.NamedTemporaryFile(suffix=".png") as temp_file:
                fig.write_image(temp_file.name, engine="kaleido")

                # Assert that the temporary file exists
                assert os.path.exists(temp_file.name)
                # Assert that the file is a valid PNG
                assert is_png(temp_file.name)
            EOF

              # Run the test script with the packaged Python interpreter
              ${python.interpreter} test_kaleido.py
          '';

          pythonImportsCheck = ["kaleido"];
          meta = with lib; {
            description = "Fast static image export for web-based visualization libraries with zero dependencies";
            homepage = "https://github.com/plotly/Kaleido";
            license = licenses.mit;
          };
        };
      pythonEnv = python.withPackages (ps: [kaleido]);
    in {
      packages.kaleido = kaleido;
      devShell = pkgs.mkShell {
        buildInputs = [pythonEnv];
      };
    });
}
