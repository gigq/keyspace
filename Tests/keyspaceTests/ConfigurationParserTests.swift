import Carbon
import Testing
@testable import keyspace

@Test
func parsesDefaultStyleBindings() throws {
    let parser = ConfigurationParser()
    let configuration = try parser.parse(
        """
        bind = cmd+enter, launch, com.mitchellh.ghostty
        bind = shift+cmd+10, move-window-to-space, 10
        bind = shift+cmd+option+3, move-window-to-secondary-space, 3
        bind = shift+cmd+t, tile-current-display-master
        bind = mouse-4, tile-current-display-master
        """
    )

    #expect(configuration.bindings.count == 5)
    #expect(configuration.bindings[0].action == .launch("com.mitchellh.ghostty"))
    #expect(configuration.bindings[1].action == .moveWindowToSpace(10))
    if case let .key(keyCombo) = configuration.bindings[1].trigger {
        #expect(keyCombo.keyCode == UInt32(kVK_ANSI_0))
    } else {
        Issue.record("Expected a keyboard trigger for the desktop-10 binding")
    }
    #expect(configuration.bindings[2].action == .moveWindowToSecondarySpace(3))
    if case let .key(keyCombo) = configuration.bindings[2].trigger {
        #expect(keyCombo.modifiers.contains(.option))
    } else {
        Issue.record("Expected a keyboard trigger for the secondary-display binding")
    }
    #expect(configuration.bindings[3].action == .tileCurrentDisplayMaster)
    if case let .mouse(mouseTrigger) = configuration.bindings[4].trigger {
        #expect(mouseTrigger.buttonNumber == 4)
        #expect(mouseTrigger.rawValue == "mouse-4")
    } else {
        Issue.record("Expected a mouse trigger for the mouse4 binding")
    }
}

@Test
func rejectsUnknownActions() throws {
    let parser = ConfigurationParser()

    #expect(throws: ConfigurationError.self) {
        try parser.parse("bind = cmd+enter, nope, value")
    }
}
