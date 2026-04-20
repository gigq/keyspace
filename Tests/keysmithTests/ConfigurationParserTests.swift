import Carbon
import Testing
@testable import keysmith

@Test
func parsesDefaultStyleBindings() throws {
    let parser = ConfigurationParser()
    let configuration = try parser.parse(
        """
        bind = cmd+enter, launch, com.mitchellh.ghostty
        bind = shift+cmd+10, move-window-to-space, 10
        """
    )

    #expect(configuration.bindings.count == 2)
    #expect(configuration.bindings[0].action == .launch("com.mitchellh.ghostty"))
    #expect(configuration.bindings[1].action == .moveWindowToSpace(10))
    #expect(configuration.bindings[1].keyCombo.keyCode == UInt32(kVK_ANSI_0))
}

@Test
func rejectsUnknownActions() throws {
    let parser = ConfigurationParser()

    #expect(throws: ConfigurationError.self) {
        try parser.parse("bind = cmd+enter, nope, value")
    }
}
