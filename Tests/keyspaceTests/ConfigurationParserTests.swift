import Carbon
import Testing
@testable import keyspace

@Test
func parsesDefaultStyleBindings() throws {
    let parser = ConfigurationParser()
    let configuration = try parser.parse(
        """
        bind = cmd+enter, launch, com.mitchellh.ghostty
        bind = cmd+1, switch-to-space, 1
        bind = shift+cmd+10, move-window-to-space, 10
        bind = shift+cmd+t, tile-current-display-master
        bind = mouse-4, tile-current-display-master
        bind = scroll-left, switch-space-left
        bind = scroll-right, switch-space-right
        """
    )

    #expect(configuration.bindings.count == 7)
    #expect(configuration.bindings[0].action == .launch("com.mitchellh.ghostty"))
    #expect(configuration.bindings[1].action == .switchToSpace(1))
    if case let .key(keyCombo) = configuration.bindings[1].trigger {
        #expect(keyCombo.keyCode == UInt32(kVK_ANSI_1))
    } else {
        Issue.record("Expected a keyboard trigger for the switch-to-space binding")
    }
    #expect(configuration.bindings[2].action == .moveWindowToSpace(10))
    if case let .key(keyCombo) = configuration.bindings[2].trigger {
        #expect(keyCombo.keyCode == UInt32(kVK_ANSI_0))
    } else {
        Issue.record("Expected a keyboard trigger for the desktop-10 binding")
    }
    #expect(configuration.bindings[3].action == .tileCurrentDisplayMaster)
    if case let .mouse(mouseTrigger) = configuration.bindings[4].trigger {
        #expect(mouseTrigger.buttonNumber == 4)
        #expect(mouseTrigger.rawValue == "mouse-4")
    } else {
        Issue.record("Expected a mouse trigger for the mouse4 binding")
    }
    #expect(configuration.bindings[5].action == .switchSpaceLeft)
    if case let .scroll(scrollTrigger) = configuration.bindings[5].trigger {
        #expect(scrollTrigger.direction == .left)
    } else {
        Issue.record("Expected a scroll trigger for the scroll-left binding")
    }
    #expect(configuration.bindings[6].action == .switchSpaceRight)
    if case let .scroll(scrollTrigger) = configuration.bindings[6].trigger {
        #expect(scrollTrigger.direction == .right)
    } else {
        Issue.record("Expected a scroll trigger for the scroll-right binding")
    }
}

@Test
func rejectsUnknownActions() throws {
    let parser = ConfigurationParser()

    #expect(throws: ConfigurationError.self) {
        try parser.parse("bind = cmd+enter, nope, value")
    }
}
