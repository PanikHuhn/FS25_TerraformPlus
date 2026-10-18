-- Terraform Plus | v0.0.1.0
-- Sicherer Einstieg: Dieses Skript veraendert KEIN Gelaende.
-- Es prueft nur, ob LS25 den Mod und die Map-Events laedt.

TerraformPlus = TerraformPlus or {}

function TerraformPlus:loadMap()
    print("[Terraform Plus] loadMap: Mod erfolgreich geladen (v0.0.1.0)")
end

function TerraformPlus:deleteMap()
    print("[Terraform Plus] deleteMap: Karte entladen")
end

addModEventListener(TerraformPlus)
