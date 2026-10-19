import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
from check_architecture import graph_for


class Boundaries(unittest.TestCase):
    def test_allowed_application_to_domain(self):
        graph_for({
            "server/application/Action.luau": "--!strict\nreturn require(script.Parent.Parent.domain.Rule)",
            "server/domain/Rule.luau": "--!strict\nreturn {}",
        })

    def test_domain_cannot_import_adapter(self):
        with self.assertRaisesRegex(ValueError, "forbidden"):
            graph_for({
                "server/domain/Rule.luau": "--!strict\nreturn require(script.Parent.Parent.adapters.World)",
                "server/adapters/World.luau": "--!strict\nreturn {}",
            })

    def test_client_cannot_import_server(self):
        with self.assertRaisesRegex(ValueError, "forbidden"):
            graph_for({
                "client/View.luau": "--!strict\nreturn require(script.Parent.Parent.server.Secret)",
                "server/Secret.luau": "--!strict\nreturn {}",
            })

    def test_cycle(self):
        with self.assertRaisesRegex(ValueError, "cycle"):
            graph_for({
                "shared/A.luau": "--!strict\nreturn require(script.Parent.B)",
                "shared/B.luau": "--!strict\nreturn require(script.Parent.A)",
            })

    def test_alias_is_not_silently_ignored(self):
        with self.assertRaisesRegex(ValueError, "unsupported"):
            graph_for({"shared/A.luau": "--!strict\nlocal target = script.Parent.B\nreturn require(target)"})

    def test_inner_layer_engine_access(self):
        with self.assertRaisesRegex(ValueError, "engine access"):
            graph_for({"server/application/A.luau": '--!strict\nreturn game:GetService("Workspace")'})

if __name__ == "__main__":
    unittest.main()
