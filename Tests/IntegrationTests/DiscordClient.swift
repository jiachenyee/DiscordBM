#if swift(>=5.8)
@preconcurrency import Atomics
#else
import Atomics
#endif
@testable import DiscordBM
import DiscordHTTP
import AsyncHTTPClient
import NIOCore
import XCTest

class DiscordClientTests: XCTestCase {
    
    var httpClient: HTTPClient!
    var client: (any DiscordClient)!
    
    override func setUp() async throws {
        self.httpClient = HTTPClient(eventLoopGroupProvider: .createNew)
        self.client = DefaultDiscordClient(
            httpClient: httpClient,
            token: Constants.token,
            appId: Constants.botId
        )
    }
    
    override func tearDown() async throws {
        try await httpClient.shutdown()
    }
    
    /// Just here so you know.
    /// We can't initiate interactions with automations (not officially at least), so can't test.
    func testInteractions() { }
    
    func testGateway() async throws {
        /// Get from "gateway"
        let url = try await client.getGateway().decode().url
        XCTAssertTrue(url.contains("wss://"), "payload: \(url)")
        XCTAssertTrue(url.contains("discord"), "payload: \(url)")
        
        /// Get from "bot gateway"
        let botInfo = try await client.getGatewayBot().decode()
        
        XCTAssertTrue(botInfo.url.contains("wss://"), "payload: \(botInfo)")
        XCTAssertTrue(botInfo.url.contains("discord"), "payload: \(botInfo)")
        let limitInfo = botInfo.session_start_limit
        let numbers = [
            limitInfo.max_concurrency,
            limitInfo.remaining,
            limitInfo.total
        ]
        XCTAssertTrue(numbers.allSatisfy({ $0 != 0 }), "payload: \(botInfo)")
    }
    
    func testMessageSendDelete() async throws {
        
        /// Cleanup: Get channel messages and delete messages by the bot itself, if any
        /// Makes this test resilient to failing because it has failed the last time
        let allOldMessages = try await client.getChannelMessages(
            channelId: Constants.channelId
        ).decode()
        
        for message in allOldMessages where message.author?.id == Constants.botId {
            try await client.deleteMessage(
                channelId: message.channel_id,
                messageId: message.id
            ).guardSuccess()
        }
        
        /// Create
        let text = "Testing! \(Date())"
        let message = try await client.createMessage(
            channelId: Constants.channelId,
            payload: .init(content: text)
        ).decode()
        
        XCTAssertEqual(message.content, text)
        XCTAssertEqual(message.channel_id, Constants.channelId)
        
        /// Edit
        let newText = "Edit Testing! \(Date())"
        let edited = try await client.editMessage(
            channelId: Constants.channelId,
            messageId: message.id,
            payload: .init(embeds: [
                .init(description: newText)
            ])
        ).decode()
        
        XCTAssertEqual(edited.content, text)
        XCTAssertEqual(edited.embeds.first?.description, newText)
        XCTAssertEqual(edited.channel_id, Constants.channelId)
        
        /// Add 4 Reactions
        let reactions = ["🚀", "🤠", "👀", "❤️"]
        for reaction in reactions {
            let reactionResponse = try await client.createReaction(
                channelId: Constants.channelId,
                messageId: message.id,
                emoji: .unicodeEmoji(reaction)
            )
            
            XCTAssertEqual(reactionResponse.status, .noContent)
        }
        
        let deleteOwnReactionResponse = try await client.deleteOwnReaction(
            channelId: Constants.channelId,
            messageId: message.id,
            emoji: .unicodeEmoji(reactions[0])
        )
        
        XCTAssertEqual(deleteOwnReactionResponse.status, .noContent)
        
        try await client.deleteUserReaction(
            channelId: Constants.channelId,
            messageId: message.id,
            emoji: .unicodeEmoji(reactions[1]),
            userId: Constants.botId
        ).guardSuccess()
        
        let getReactionsResponse = try await client.getReactions(
            channelId: Constants.channelId,
            messageId: message.id,
            emoji: .unicodeEmoji(reactions[2])
        ).decode()
        
        XCTAssertEqual(getReactionsResponse.count, 1)
        
        let reactionUser = try XCTUnwrap(getReactionsResponse.first)
        XCTAssertEqual(reactionUser.id, Constants.botId)
        
        let deleteAllReactionsForEmojiResponse = try await client.deleteAllReactionsForEmoji(
            channelId: Constants.channelId,
            messageId: message.id,
            emoji: .unicodeEmoji(reactions[2])
        )
        
        XCTAssertEqual(deleteAllReactionsForEmojiResponse.status, .noContent)
        
        let deleteAllReactionsResponse = try await client.deleteAllReactions(
            channelId: Constants.channelId,
            messageId: message.id
        )
        
        XCTAssertEqual(deleteAllReactionsResponse.status, .noContent)
        
        /// Get the message again
        let retrievedMessage = try await client.getChannelMessage(
            channelId: Constants.channelId,
            messageId: message.id
        ).decode()
        
        XCTAssertEqual(retrievedMessage.id, edited.id)
        XCTAssertEqual(retrievedMessage.content, edited.content)
        XCTAssertEqual(retrievedMessage.channel_id, edited.channel_id)
        XCTAssertEqual(retrievedMessage.embeds.first?.description, edited.embeds.first?.description)
        XCTAssertFalse(retrievedMessage.reactions?.isEmpty == false)
        
        /// Get channel messages
        let allMessages = try await client.getChannelMessages(
            channelId: Constants.channelId
        ).decode()
        
        XCTAssertGreaterThan(allMessages.count, 2)
        XCTAssertEqual(allMessages[0].id, edited.id)
        XCTAssertEqual(allMessages[1].content, "And this is another test message :\\)")
        XCTAssertEqual(allMessages[2].content, "Hello! This is a test message!")
        
        /// Get channel messages with `limit == 2`
        let allMessagesLimit = try await client.getChannelMessages(
            channelId: Constants.channelId,
            limit: 2
        ).decode()
        
        XCTAssertEqual(allMessagesLimit.count, 2)
        
        /// Get channel messages with `after`
        let allMessagesAfter = try await client.getChannelMessages(
            channelId: Constants.channelId,
            after: allMessages[1].id
        ).decode()
        
        XCTAssertEqual(allMessagesAfter.count, 1)
        
        /// Get channel messages with `before`
        let allMessagesBefore = try await client.getChannelMessages(
            channelId: Constants.channelId,
            before: allMessages[2].id
        ).decode()
        
        XCTAssertEqual(allMessagesBefore.count, 0)
        
        /// Get channel messages with `around`
        let allMessagesAround = try await client.getChannelMessages(
            channelId: Constants.channelId,
            around: allMessages[1].id
        ).decode()
        
        XCTAssertEqual(allMessagesAround.count, 3)
        
        /// Delete
        let deletionResponse = try await client.deleteMessage(
            channelId: Constants.channelId,
            messageId: message.id,
            reason: "Random reason " + UUID().uuidString
        )
        
        XCTAssertEqual(deletionResponse.status, .noContent)
    }
    
    func testGlobalApplicationCommands() async throws {
        /// Cleanup before start
        for command in try await client.getGlobalApplicationCommands().decode() {
            try await client.deleteGlobalApplicationCommand(commandId: command.id).guardSuccess()
        }
        
        /// Create
        let commandName1 = "test-command"
        let commandDesc1 = "Testing!"
        let command1 = try await client.createGlobalApplicationCommand(
            payload: .init(
                name: commandName1,
                description: commandDesc1,
                description_localizations: [
                    .spanish: "ES_\(commandDesc1)",
                    .german: "DE_\(commandDesc1)"
                ]
            )
        ).decode()
        
        XCTAssertEqual(command1.name, commandName1)
        XCTAssertEqual(command1.description, commandDesc1)
        XCTAssertEqual(command1.description_localizations?.values.count, 2)
        
        /// Get one
        let oneCommand = try await client.getGlobalApplicationCommand(
            commandId: command1.id
        ).decode()
        XCTAssertEqual(oneCommand.name, commandName1)
        XCTAssertEqual(oneCommand.description, commandDesc1)
        
        /// Edit
        let commandName2 = "test-command-2"
        let command2 = try await client.editGlobalApplicationCommand(
            commandId: command1.id,
            payload: .init(name: commandName2)
        ).decode()
        
        XCTAssertEqual(command2.name, commandName2)
        
        /// Get all
        let allCommands = try await client.getGlobalApplicationCommands().decode()
        
        XCTAssertEqual(allCommands.count, 1)
        let retrievedCommand1 = try XCTUnwrap(allCommands.first)
        XCTAssertEqual(retrievedCommand1.name, commandName2)
        XCTAssertEqual(retrievedCommand1.description, commandDesc1)
        
        /// Bulk overwrite
        let commandName3 = "test-command-3"
        let commandType3: ApplicationCommand.Kind = .user
        let overwrite = try await client.bulkOverwriteGlobalApplicationCommands(
            payload: [.init(
                name: commandName3,
                type: commandType3
            )]
        ).decode()
        
        XCTAssertEqual(overwrite.count, 1)
        let overwriteCommand1 = try XCTUnwrap(overwrite.first)
        XCTAssertEqual(overwriteCommand1.name, commandName3)
        XCTAssertEqual(overwriteCommand1.type, commandType3)
        
        /// Delete
        let commandId = try XCTUnwrap(overwriteCommand1.id)
        let deletionResponse = try await client.deleteGlobalApplicationCommand(
            commandId: commandId
        )
        XCTAssertEqual(deletionResponse.status, .noContent)
    }
    
    func testGuildApplicationCommands() async throws {
        /// Cleanup before start
        for command in try await client.getGuildApplicationCommands(
            guildId: Constants.guildId
        ).decode() {
            try await client.deleteGuildApplicationCommand(
                guildId: Constants.guildId,
                commandId: command.id
            ).guardSuccess()
        }
        
        /// Create
        let commandName1 = "test-guild-command"
        let commandDesc1 = "Testing!"
        let command1 = try await client.createGuildApplicationCommand(
            guildId: Constants.guildId,
            payload: .init(
                name: commandName1,
                description: commandDesc1,
                description_localizations: [
                    .spanish: "ES_\(commandDesc1)",
                    .german: "DE_\(commandDesc1)"
                ]
            )
        ).decode()
        
        XCTAssertEqual(command1.name, commandName1)
        XCTAssertEqual(command1.description, commandDesc1)
        XCTAssertEqual(command1.description_localizations?.values.count, 2)
        
        /// Get one
        let oneCommand = try await client.getGuildApplicationCommand(
            guildId: Constants.guildId,
            commandId: command1.id
        ).decode()
        XCTAssertEqual(oneCommand.name, commandName1)
        XCTAssertEqual(oneCommand.description, commandDesc1)
        
        /// Get permissions. Will be empty since we can't set up permissions using bot tokens
        let allPerms = try await client.getGuildApplicationCommandPermissions(
            guildId: Constants.guildId
        ).decode()
        
        XCTAssertTrue(allPerms.isEmpty)
        
        /// Get one permission. Will throw an error
        /// since we can't set up permissions using bot tokens
        let onePerm = try await client.getApplicationCommandPermissions(
            guildId: Constants.guildId,
            commandId: command1.id
        ).decodeError()
        
        switch onePerm {
        case .jsonError(let jsonError) where
            jsonError.code == .unknownApplicationCommandPermissions:
            break
        default:
            XCTFail("Discord threw unexpected error: \(onePerm)")
        }
        
        /// Edit
        let commandName2 = "test-guild-command-2"
        let command2 = try await client.editGuildApplicationCommand(
            guildId: Constants.guildId,
            commandId: command1.id,
            payload: .init(name: commandName2)
        ).decode()
        
        XCTAssertEqual(command2.name, commandName2)
        
        /// Get all
        let allCommands = try await client.getGuildApplicationCommands(
            guildId: Constants.guildId
        ).decode()
        
        XCTAssertEqual(allCommands.count, 1)
        let retrievedCommand1 = try XCTUnwrap(allCommands.first)
        XCTAssertEqual(retrievedCommand1.name, commandName2)
        XCTAssertEqual(retrievedCommand1.description, commandDesc1)
        
        /// Bulk overwrite
        let commandName3 = "test-guild-command-3"
        let commandType3: ApplicationCommand.Kind = .user
        let overwrite = try await client.bulkOverwriteGuildApplicationCommands(
            guildId: Constants.guildId,
            payload: [.init(
                name: commandName3,
                type: commandType3
            )]
        ).decode()
        
        XCTAssertEqual(overwrite.count, 1)
        let overwriteCommand1 = try XCTUnwrap(overwrite.first)
        XCTAssertEqual(overwriteCommand1.name, commandName3)
        XCTAssertEqual(overwriteCommand1.type, commandType3)
        
        /// Delete
        let commandId = try XCTUnwrap(overwriteCommand1.id)
        let deletionResponse = try await client.deleteGuildApplicationCommand(
            guildId: Constants.guildId,
            commandId: commandId
        )
        XCTAssertEqual(deletionResponse.status, .noContent)
    }
    
    func testGuildAndChannel() async throws {
        /// Get
        let guild = try await client.getGuild(
            id: Constants.guildId,
            withCounts: false
        ).decode()
        
        XCTAssertEqual(guild.id, Constants.guildId)
        XCTAssertEqual(guild.name, Constants.guildName)
        XCTAssertEqual(guild.approximate_member_count, nil)
        XCTAssertEqual(guild.approximate_presence_count, nil)
        
        /// Get with counts
        let guildWithCounts = try await client.getGuild(
            id: Constants.guildId,
            withCounts: true
        ).decode()
        
        XCTAssertEqual(guildWithCounts.id, Constants.guildId)
        XCTAssertEqual(guildWithCounts.name, Constants.guildName)
        XCTAssertEqual(guildWithCounts.approximate_member_count, 3)
        XCTAssertNotEqual(guildWithCounts.approximate_presence_count, nil)
        
        /// Get guild audit logs
        let auditLogs = try await client.getGuildAuditLogs(guildId: Constants.guildId).decode()
        XCTAssertEqual(auditLogs.audit_log_entries.count, 50)
        
        /// Leave guild
        /// Can't leave guild so will just do a bad-request
        let leaveGuild = try await client.leaveGuild(id: Constants.guildId + "1111")
        
        XCTAssertEqual(leaveGuild.status, .badRequest)
        
        /// Get channel
        let channel = try await client.getChannel(id: Constants.channelId).decode()
        
        XCTAssertEqual(channel.id, Constants.channelId)
        
        /// Get member
        let member = try await client.getGuildMember(
            guildId: Constants.guildId,
            userId: Constants.personalId
        ).decode()
        
        XCTAssertEqual(member.user?.id, Constants.personalId)
        
        /// Search Guild members
        let search = try await client.searchGuildMembers(
            guildId: Constants.guildId,
            query: "Mahdi",
            limit: nil
        ).decode()
        
        XCTAssertTrue([1, 2].contains(search.count))
        XCTAssertTrue(search.allSatisfy({ $0.user?.username.contains("Mahdi") == true }))
        
        /// Search Guild members with invalid limit
        do {
            _ = try await client.searchGuildMembers(
                guildId: Constants.guildId,
                query: "Mahdi",
                limit: 10_000
            )
            XCTFail("'searchGuildMembers' must fail with too-big limits")
        } catch {
            switch error {
            case DiscordHTTPError.queryParameterOutOfBounds(
                name: "limit",
                value: "10000",
                lowerBound: 1,
                upperBound: 1_000
            ):
                break
            default:
                XCTFail("Unexpected fail error: \(error)")
            }
        }
        
        /// Create new role
        let rolePayload = RequestBody.CreateGuildRole(
            name: "test_role",
            permissions: [.addReactions, .attachFiles, .banMembers, .changeNickname],
            color: .init(red: 100, green: 100, blue: 100)!,
            hoist: true,
            unicode_emoji: nil, // Needs a boosted server
            mentionable: true
        )
        let role = try await client.createGuildRole(
            guildId: Constants.guildId,
            payload: rolePayload
        ).decode()
        
        XCTAssertEqual(role.name, rolePayload.name)
        XCTAssertEqual(role.permissions.toBitValue(), rolePayload.permissions!.toBitValue())
        XCTAssertEqual(role.color.value, rolePayload.color!.value)
        XCTAssertEqual(role.hoist, rolePayload.hoist)
        XCTAssertEqual(role.unicode_emoji, rolePayload.unicode_emoji)
        XCTAssertEqual(role.mentionable, rolePayload.mentionable)
        
        /// Get guild roles
        let guildRoles = try await client.getGuildRoles(id: Constants.guildId).decode()
        let rolesWithName = guildRoles.filter({ $0.name == role.name })
        XCTAssertGreaterThanOrEqual(rolesWithName.count, 1)
        
        /// Add role to member
        let memberRoleAdditionResponse = try await client.addGuildMemberRole(
            guildId: Constants.guildId,
            userId: Constants.personalId,
            roleId: role.id
        )
        
        XCTAssertEqual(memberRoleAdditionResponse.status, .noContent)
        
        let memberRoleDeletionResponse = try await client.removeGuildMemberRole(
            guildId: Constants.guildId,
            userId: Constants.personalId,
            roleId: role.id
        )
        
        XCTAssertEqual(memberRoleDeletionResponse.status, .noContent)
        
        /// Delete role
        let reason = "Random reason " + UUID().uuidString
        let roleDeletionResponse = try await client.deleteGuildRole(
            guildId: Constants.guildId,
            roleId: role.id,
            reason: reason
        )
        
        XCTAssertEqual(roleDeletionResponse.status, .noContent)
        
        /// Get guild audit logs with action type
        let auditLogsWithActionType = try await client.getGuildAuditLogs(
            guildId: Constants.guildId,
            action_type: .roleDelete
        ).decode()
        
        let entries = auditLogsWithActionType.audit_log_entries
        XCTAssertTrue(entries.contains(where: { $0.reason == reason }), "Entries: \(entries)")
    }
    
    func testDMs() async throws {
        /// Create DM
        let response = try await client.createDM(recipient_id: Constants.personalId).decode()
        
        XCTAssertEqual(response.type, .dm)
        let recipient = try XCTUnwrap(response.recipients?.first)
        XCTAssertEqual(recipient.id, Constants.personalId)
        
        /// Send a message to the DM channel
        let text = "Testing! \(Date())"
        let message = try await client.createMessage(
            channelId: response.id,
            payload: .init(content: text)
        ).decode()
        
        XCTAssertEqual(message.content, text)
        XCTAssertEqual(message.channel_id, response.id)
    }
    
    func testThreads() async throws {
        
        /// Create a message for creating a thread
        let message = try await client.createMessage(
            channelId: Constants.threadsChannelId,
            payload: .init(content: "Thread-test Message")
        ).decode()
        
        /// Create Thread
        let thread = try await client.startThreadFromMessage(
            channelId: Constants.threadsChannelId,
            messageId: message.id,
            reason: "Testing!",
            payload: .init(
                name: "Creating a Thread to Test!",
                auto_archive_duration: .threeDays,
                rate_limit_per_user: 2
            )
        ).decode()
        
        do {
            let text = "Testing! \(Date())"
            let message = try await client.createMessage(
                channelId: thread.id,
                payload: .init(content: text)
            ).decode()
            
            XCTAssertEqual(message.content, text)
            XCTAssertEqual(message.channel_id, thread.id)
            
            /// Edit
            let newText = "Edit Testing! \(Date())"
            let edited = try await client.editMessage(
                channelId: thread.id,
                messageId: message.id,
                payload: .init(embeds: [
                    .init(description: newText)
                ])
            ).decode()
            
            XCTAssertEqual(edited.content, text)
            XCTAssertEqual(edited.embeds.first?.description, newText)
            XCTAssertEqual(edited.channel_id, thread.id)
            
            /// Delete
            try await client.deleteMessage(
                channelId: thread.id,
                messageId: message.id,
                reason: "Random reason " + UUID().uuidString
            ).guardSuccess()
        }
        
        try await client.addThreadMember(
            threadId: thread.id,
            userId: Constants.personalId
        ).guardSuccess()
        
        let threadMember = try await client.getThreadMember(
            threadId: thread.id,
            userId: Constants.personalId
        ).decode()
        
        XCTAssertEqual(threadMember.user_id, Constants.personalId)
        
        let threadMemberWithMember = try await client.getThreadMemberWithMember(
            threadId: thread.id,
            userId: Constants.personalId
        ).decode()
        
        XCTAssertEqual(threadMemberWithMember.user_id, Constants.personalId)
        XCTAssertNotNil(threadMemberWithMember.member.user?.id, Constants.personalId)
        
        let allThreadMembers = try await client.listThreadMembers(threadId: thread.id).decode()
        
        guard allThreadMembers.count == 2 else {
            XCTFail("Expected 2 thread member but got \(allThreadMembers.count)")
            return
        }
        
        let allThreadMembersAfter = try await client.listThreadMembersWithMember(
            threadId: thread.id,
            after: allThreadMembers[0].user_id!
        ).decode()
        
        XCTAssertEqual(allThreadMembersAfter.count, 1)
        let otherUser = [Constants.personalId, Constants.botId].filter {
            $0 != allThreadMembers[0].user_id!
        }
        XCTAssertEqual(allThreadMembersAfter.first?.user_id, otherUser[0])
        
        let limitedThreadMembers = try await client.listThreadMembersWithMember(
            threadId: thread.id,
            limit: 1
        ).decode()
        
        XCTAssertEqual(limitedThreadMembers.count, 1)
        
        try await client.leaveThread(id: thread.id)
            .guardSuccess()
        
        let threadMembersLeft = try await client.listThreadMembers(threadId: thread.id).decode()
        
        XCTAssertEqual(threadMembersLeft.first?.user_id, Constants.personalId)
        
        try await client.joinThread(id: thread.id)
            .guardSuccess()
        
        let threadMembersRejoined = try await client.listThreadMembers(threadId: thread.id).decode()
        
        XCTAssertEqual(threadMembersRejoined.count, 2)
        
        try await client.removeThreadMember(
            threadId: thread.id,
            userId: Constants.personalId
        ).guardSuccess()
        
        let threadMembersRemoved = try await client.listThreadMembers(threadId: thread.id).decode()
        
        XCTAssertEqual(threadMembersRemoved.first?.user_id, Constants.botId)
        
        try await client.deleteMessage(
            channelId: Constants.threadsChannelId,
            messageId: message.id
        ).guardSuccess()
        
        let threadWithoutMessage = try await client.startThreadWithoutMessage(
            channelId: Constants.announcementsChannelId,
            reason: "Testing without message thread",
            payload: .init(
                name: "Thread test without message",
                auto_archive_duration: .oneHour,
                type: .announcementThread,
                invitable: true,
                rate_limit_per_user: 900
            )
        ).decode()
        
        _ = try await client.listPublicArchivedThreads(
            channelId: Constants.announcementsChannelId,
            before: Date(),
            limit: 2
        ).decode()
        
        /// The message-id is the same as the thread id based on what Discord says
        try await client.deleteMessage(
            channelId: Constants.announcementsChannelId,
            messageId: threadWithoutMessage.id
        ).guardSuccess()
        
        let forumThreadName = "Forum thread test"
        let forumThread = try await client.startThreadInForumChannel(
            channelId: Constants.forumChannelId,
            reason: "Forum channel thread testing",
            payload: .init(
                name: forumThreadName,
                auto_archive_duration: .oneDay,
                rate_limit_per_user: nil,
                message: .init(content: "Hello!"),
                applied_tags: nil
            )
        ).decode()
        
        XCTAssertEqual(forumThread.name, forumThreadName)
        
        try await client.listPublicArchivedThreads(
            channelId: Constants.threadsChannelId,
            before: Date().addingTimeInterval(-60),
            limit: 2
        ).guardSuccess()
        
        try await client.listPrivateArchivedThreads(
            channelId: Constants.threadsChannelId,
            before: Date().addingTimeInterval(-3_600),
            limit: 2
        ).guardSuccess()
        
        try await client.listJoinedPrivateArchivedThreads(
            channelId: Constants.threadsChannelId,
            limit: 2
        ).guardSuccess()
    }
    
    func testWebhooks() async throws {
        
        /// Cleanup before starting the actual tests
        do {
            let guildWebhooks = try await client.getGuildWebhooks(
                guildId: Constants.guildId
            ).decode()
            
            for webhook in guildWebhooks {
                try await client.deleteWebhook(id: webhook.id)
                    .guardSuccess()
            }
        }
        
        let image1 = ByteBuffer(data: resource(name: "discordbm-logo.png"))
        let image2 = ByteBuffer(data: resource(name: "1kb.png"))
        
        let webhookName1 = "TestWebhook1"
        
        let webhook1 = try await client.createWebhook(
            channelId: Constants.webhooksChannelId,
            payload: .init(
                name: webhookName1,
                avatar: .init(file: .init(data: image1, filename: "DiscordBM.png"))
            )
        ).decode()
        
        XCTAssertTrue(webhook1.token?.isEmpty == false)
        XCTAssertTrue(webhook1.id.isEmpty == false)
        XCTAssertTrue(webhook1.avatar?.isEmpty == false)
        XCTAssertEqual(webhook1.name, webhookName1)
        XCTAssertEqual(webhook1.guild_id, Constants.guildId)
        XCTAssertEqual(webhook1.channel_id, Constants.webhooksChannelId)
        
        let webhookName2 = "TestWebhook2"
        
        let webhook2 = try await client.createWebhook(
            channelId: Constants.webhooksChannelId,
            payload: .init(name: webhookName2)
        ).decode()
        
        XCTAssertTrue(webhook2.token?.isEmpty == false)
        XCTAssertTrue(webhook2.id.isEmpty == false)
        XCTAssertNil(webhook2.avatar)
        XCTAssertEqual(webhook2.name, webhookName2)
        XCTAssertEqual(webhook2.guild_id, Constants.guildId)
        XCTAssertEqual(webhook2.channel_id, Constants.webhooksChannelId)
        
        let webhook1Token = try XCTUnwrap(webhook1.token)
        let webhook2Token = try XCTUnwrap(webhook2.token)
        
        let getWebhook1 = try await client.getWebhook(id: webhook1.id).decode()
        XCTAssertEqual(getWebhook1.id, webhook1.id)
        XCTAssertEqual(getWebhook1.token, webhook1.token)
        
        let getWebhook2 = try await client.getWebhook(
            address: .deconstructed(id: webhook2.id, token: webhook2Token)
        ).decode()
        XCTAssertEqual(getWebhook2.id, webhook2.id)
        XCTAssertEqual(getWebhook2.token, webhook2.token)
        
        let channelWebhooks = try await client.getChannelWebhooks(
            channelId: Constants.webhooksChannelId
        ).decode()
        
        XCTAssertEqual(channelWebhooks.count, 2)
        
        let channelWebhook1 = try XCTUnwrap(channelWebhooks.first)
        
        XCTAssertEqual(channelWebhook1.token, webhook1.token)
        XCTAssertEqual(channelWebhook1.id, webhook1.id)
        
        let channelWebhook2 = try XCTUnwrap(channelWebhooks.last)
        
        XCTAssertEqual(channelWebhook2.token, webhook2.token)
        XCTAssertEqual(channelWebhook2.id, webhook2.id)
        
        let guildWebhooks = try await client.getGuildWebhooks(
            guildId: Constants.guildId
        ).decode()
        
        XCTAssertEqual(guildWebhooks.count, 2)
        
        let guildWebhook1 = try XCTUnwrap(guildWebhooks.first)
        
        XCTAssertEqual(guildWebhook1.token, webhook1.token)
        XCTAssertEqual(guildWebhook1.id, webhook1.id)
        
        let guildWebhook2 = try XCTUnwrap(guildWebhooks.last)
        
        XCTAssertEqual(guildWebhook2.token, webhook2.token)
        XCTAssertEqual(guildWebhook2.id, webhook2.id)
        
        let webhookNewName1 = "WebhookTestNew1"
        let modify1 = try await client.modifyWebhook(
            id: webhook1.id,
            payload: .init(
                name: webhookNewName1,
                avatar: .init(file: .init(data: image2, filename: "1kb.png")),
                channel_id: Constants.webhooks2ChannelId
            )
        ).decode()
        
        XCTAssertEqual(modify1.token, webhook1.token)
        XCTAssertEqual(modify1.id, webhook1.id)
        XCTAssertTrue(modify1.avatar?.isEmpty == false)
        XCTAssertNotEqual(modify1.avatar, webhook1.avatar)
        XCTAssertEqual(modify1.name, webhookNewName1)
        XCTAssertEqual(modify1.guild_id, Constants.guildId)
        XCTAssertEqual(modify1.channel_id, Constants.webhooks2ChannelId)
        
        let webhookNewName2 = "WebhookTestNew2"
        let modify2 = try await client.modifyWebhook(
            address: .deconstructed(id: webhook2.id, token: webhook2Token),
            payload: .init(name: webhookNewName2)
        ).decode()
        
        XCTAssertEqual(modify2.token, webhook2.token)
        XCTAssertEqual(modify2.id, webhook2.id)
        XCTAssertNil(modify2.avatar)
        XCTAssertEqual(modify2.name, webhookNewName2)
        XCTAssertEqual(modify2.guild_id, Constants.guildId)
        XCTAssertEqual(modify2.channel_id, Constants.webhooksChannelId)
        
        let noContentResponse = try await client.executeWebhook(
            address: .deconstructed(id: webhook1.id, token: webhook1Token),
            payload: .init(content: "Testing! \(Date())")
        )
        XCTAssertEqual(noContentResponse.status, .noContent)
        
        let text = "Testing! \(Date())"
        let date = Date()
        let message = try await client.executeWebhookWithResponse(
            address: .deconstructed(id: webhook1.id, token: webhook1Token),
            payload: .init(
                content: text,
                embeds: [.init(title: "Hey", timestamp: date)]
            )
        ).decode()
        
        XCTAssertEqual(message.channel_id, Constants.webhooks2ChannelId)
        XCTAssertEqual(message.content, text)
        XCTAssertEqual(message.embeds.first?.title, "Hey")
        let timestamp = try XCTUnwrap(message.embeds.first?.timestamp?.date).timeIntervalSince1970
        let range = (date.timeIntervalSince1970-1)...(date.timeIntervalSince1970+1)
        XCTAssertTrue(range.contains(timestamp), "\(range) did not contain \(timestamp)")
        
        let text2 = "Testing! \(Date())"
        let threadId = "1066278441256751114"
        let threadMessage = try await client.executeWebhookWithResponse(
            address: .deconstructed(id: webhook2.id, token: webhook2Token),
            threadId: threadId,
            payload: .init(content: text2)
        ).decode()
        
        XCTAssertEqual(threadMessage.channel_id, threadId)
        XCTAssertEqual(threadMessage.content, text2)
        
        let getMessage = try await client.getWebhookMessage(
            address: .deconstructed(id: webhook1.id, token: webhook1Token),
            messageId: message.id
        ).decode()
        
        XCTAssertEqual(getMessage.id, message.id)
        XCTAssertEqual(getMessage.content, message.content)
        XCTAssertEqual(getMessage.embeds.map(\.title), message.embeds.map(\.title))
        
        let newText = "Testing Edit! \(Date())"
        let editThreadMessage = try await client.editWebhookMessage(
            address: .deconstructed(id: webhook2.id, token: webhook2Token),
            messageId: threadMessage.id,
            threadId: threadId,
            payload: .init(content: newText)
        ).decode()
        
        XCTAssertEqual(editThreadMessage.content, newText)
        XCTAssertEqual(editThreadMessage.id, threadMessage.id)
        
        let getThreadMessage = try await client.getWebhookMessage(
            address: .deconstructed(id: webhook2.id, token: webhook2Token),
            messageId: threadMessage.id,
            threadId: threadId
        ).decode()
        
        XCTAssertEqual(getThreadMessage.id, threadMessage.id)
        XCTAssertEqual(getThreadMessage.content, editThreadMessage.content)
        
        let deleteThreadMessage = try await client.deleteWebhookMessage(
            address: .deconstructed(id: webhook2.id, token: webhook2Token),
            messageId: threadMessage.id,
            threadId: threadId
        )
        XCTAssertNoThrow(try deleteThreadMessage.guardSuccess())
        
        let delete1 = try await client.deleteWebhook(id: webhook1.id, reason: "Testing! 1")
        XCTAssertNoThrow(try delete1.guardSuccess())
        
        let delete2 = try await client.deleteWebhook(
            address: .deconstructed(id: webhook2.id, token: webhook2Token),
            reason: "Testing! 2"
        )
        XCTAssertNoThrow(try delete2.guardSuccess())
    }
    
    /// Couldn't find test-cases for some of the functions
    func testCDN() async throws {
        do {
            let file = try await client.getCDNCustomEmoji(
                emojiId: "1073704788400820324"
            ).getFile()
            XCTAssertGreaterThan(file.data.readableBytes, 10)
            XCTAssertEqual(file.extension, "png")
            XCTAssertEqual(file.filename, "1073704788400820324.png")
        }
        
        do {
            let file = try await client.getCDNGuildIcon(
                guildId: "922186320275722322",
                icon: "a_6367dd2460a846748ad133206c910da5"
            ).getFile(overrideName: "guildIcon")
            XCTAssertGreaterThan(file.data.readableBytes, 10)
            XCTAssertEqual(file.extension, "gif")
            XCTAssertEqual(file.filename, "guildIcon.gif")
        }
        
        do {
            let file = try await client.getCDNGuildSplash(
                guildId: "922186320275722322",
                splash: "276ba186b5208a74344706941eb7fe8d"
            ).getFile()
            XCTAssertGreaterThan(file.data.readableBytes, 10)
        }
        
        do {
            let file = try await client.getCDNGuildDiscoverySplash(
                guildId: "922186320275722322",
                splash: "178be4921b08b761d9d9d6117c6864e2"
            ).getFile()
            XCTAssertGreaterThan(file.data.readableBytes, 10)
        }
        
        do {
            let file = try await client.getCDNGuildBanner(
                guildId: "922186320275722322",
                banner: "6e2e4d93e102a997cc46d15c28b0dfa0"
            ).getFile()
            XCTAssertGreaterThan(file.data.readableBytes, 10)
        }
        
//        do {
//            let file = try await client.getCDNUserBanner(
//                userId: String,
//                banner: String
//            ).getFile()
//            XCTAssertGreaterThan(file.data.readableBytes, 10)
//        }
        
        do {
            let file = try await client.getCDNDefaultUserAvatar(
                discriminator: 0517
            ).getFile()
            XCTAssertGreaterThan(file.data.readableBytes, 10)
            XCTAssertEqual(file.extension, "png")
        }
        
        do {
            let file = try await client.getCDNUserAvatar(
                userId: "290483761559240704",
                avatar: "2df0a0198e00ba23bf2dc728c4db94d9"
            ).getFile()
            XCTAssertGreaterThan(file.data.readableBytes, 10)
        }
        
        do {
            let file = try await client.getCDNGuildMemberAvatar(
                guildId: "922186320275722322",
                userId: "816681064855502868",
                avatar: "b94e12ce3debd281000d5291eec2b502"
            ).getFile()
            XCTAssertGreaterThan(file.data.readableBytes, 10)
        }
        
//        do {
//            let file = try await client.getCDNApplicationIcon(
//                appId: String, icon: String
//            ).getFile()
//            XCTAssertGreaterThan(file.data.readableBytes, 10)
//        }
//
//        do {
//            let file = try await client.getCDNApplicationCover(
//                appId: String, cover: String
//            ).getFile()
//            XCTAssertGreaterThan(file.data.readableBytes, 10)
//        }
        
        do {
            let file = try await client.getCDNApplicationAsset(
                appId: "401518684763586560",
                assetId: "920476458709819483"
            ).getFile()
            XCTAssertGreaterThan(file.data.readableBytes, 10)
        }
        
//        do {
//            let file = try await client.getCDNAchievementIcon(
//                appId: String, achievementId: String, icon: String
//            ).getFile()
//            XCTAssertGreaterThan(file.data.readableBytes, 10)
//        }
        
//        do {
//            let file = try await client.getCDNStorePageAsset(
//                appId: String,
//                assetId: String
//            ).getFile()
//            XCTAssertGreaterThan(file.data.readableBytes, 10)
//        }
        
//        do {
//            let file = try await client.getCDNStickerPackBanner(
//                assetId: String
//            ).getFile()
//            XCTAssertGreaterThan(file.data.readableBytes, 10)
//        }
        
//        do {
//            let file = try await client.getCDNTeamIcon(
//                teamId: String, icon: String
//            ).getFile()
//            XCTAssertGreaterThan(file.data.readableBytes, 10)
//        }
        
        do {
            let file = try await client.getCDNSticker(
                stickerId: "975144332535406633"
            ).getFile()
            XCTAssertGreaterThan(file.data.readableBytes, 10)
        }
        
        do {
            let file = try await client.getCDNRoleIcon(
                roleId: "984557789999407214",
                icon: "2cba6c72f7abd52885359054e09ab7a2"
            ).getFile()
            XCTAssertGreaterThan(file.data.readableBytes, 10)
        }
        
//        do {
//            let file = try await client.getCDNGuildScheduledEventCover(
//                eventId: String, cover: String
//            ).getFile()
//            XCTAssertGreaterThan(file.data.readableBytes, 10)
//        }
//
//        do {
//            let file = try await client.getCDNGuildMemberBanner(
//                guildId: String, userId: String, banner: String
//            ).getFile()
//            XCTAssertGreaterThan(file.data.readableBytes, 10)
//        }
    }
    
    func testMultipartPayload() async throws {
        let image = ByteBuffer(data: resource(name: "discordbm-logo.png"))
        
        do {
            let response = try await client.createMessage(
                channelId: Constants.spamChannelId,
                payload: .init(
                    content: "Multipart message!",
                    files: [.init(data: image, filename: "discordbm.png")],
                    attachments: [.init(index: 0, description: "Test attachment!")]
                )
            ).decode()
            
            XCTAssertEqual(response.content, "Multipart message!")
            XCTAssertEqual(response.attachments.count, 1)
            
            let attachment = try XCTUnwrap(response.attachments.first)
            XCTAssertEqual(attachment.filename, "discordbm.png")
            XCTAssertEqual(attachment.description, "Test attachment!")
            XCTAssertEqual(attachment.content_type, "image/png")
            XCTAssertGreaterThan(attachment.size, 20_000)
            XCTAssertEqual(attachment.height, 210)
            XCTAssertEqual(attachment.width, 1200)
            XCTAssertFalse(attachment.id.isEmpty)
            XCTAssertFalse(attachment.url.isEmpty)
            XCTAssertFalse(attachment.proxy_url.isEmpty)
        }
        
        do {
            let response = try await client.createMessage(
                channelId: Constants.spamChannelId,
                payload: .init(
                    content: "Multipart message!",
                    embeds: [.init(
                        title: "Multipart embed!",
                        timestamp: Date(),
                        image: .init(url: .attachment(name: "discordbm.png"))
                    )],
                    files: [.init(data: image, filename: "discordbm.png")]
                )
            ).decode()
            
            XCTAssertEqual(response.content, "Multipart message!")
            XCTAssertEqual(response.attachments.count, 0)
            
            let image = try XCTUnwrap(response.embeds.first?.image)
            XCTAssertEqual(image.height, 210)
            XCTAssertEqual(image.width, 1200)
            XCTAssertFalse(image.url.asString.isEmpty)
            XCTAssertFalse(image.proxy_url?.isEmpty == true)
        }
    }
    
    /// Rate-limiting has theoretical tests too, but this tests it in a practical situation.
    func testRateLimitedInPractice() async throws {
        let content = "Spamming! \(Date())"
        let rateLimitedErrors = ManagedAtomic(0)
        let count = 50
        let container = Container(targetCounter: count)
        
        let client: any DiscordClient = DefaultDiscordClient(
            httpClient: httpClient,
            token: Constants.token,
            appId: Constants.botId,
            configuration: .init(retryPolicy: nil)
        )
        
        let isFirstRequest = ManagedAtomic(false)
        Task {
            for _ in 0..<count {
                let isFirst = isFirstRequest.load(ordering: .relaxed)
                isFirstRequest.store(false, ordering: .relaxed)
                do {
                    _ = try await client.createMessage(
                        channelId: Constants.spamChannelId,
                        payload: .init(content: content)
                    ).decode()
                    await container.increaseCounter()
                } catch {
                    await container.increaseCounter()
                    switch error {
                    case DiscordHTTPError.rateLimited:
                        rateLimitedErrors.wrappingIncrement(ordering: .relaxed)
                    case DiscordHTTPError.badStatusCode(let response)
                        where response.status == .tooManyRequests:
                        /// If its the first request and we're having this error, then
                        /// it means the last tests have exhausted our rate-limit and
                        /// it's not this test's fault.
                        if isFirst {
                            break
                        } else {
                            XCTFail("Received unexpected error: \(error)")
                        }
                    default:
                        XCTFail("Received unexpected error: \(error)")
                    }
                }
            }
        }
        
        await container.waitForCounter()
        
        XCTAssertGreaterThan(rateLimitedErrors.load(ordering: .relaxed), 0)
        XCTAssertLessThan(rateLimitedErrors.load(ordering: .relaxed), count)
        
        /// Waiting 10 seconds to make sure the next tests don't get rate-limited
        try await Task.sleep(nanoseconds: 10_000_000_000)
    }
    
    func testCachingInPractice() async throws {
        /// Caching enabled
        do {
            let cachingBehavior = ClientConfiguration.CachingBehavior.enabled(defaultTTL: 2)
            let configuration = ClientConfiguration(cachingBehavior: cachingBehavior)
            let cacheClient: any DiscordClient = DefaultDiscordClient(
                httpClient: httpClient,
                token: Constants.token,
                appId: Constants.botId,
                configuration: configuration
            )
            
            /// We create a command, fetch the commands count, then delete the command
            /// and fetch the command count again.
            /// Since we are using caching, the first command count and the second command count
            /// must be the same (although it's wrong)
            let commandName = "test-command"
            let commandDesc = "Testing!"
            let command = try await cacheClient.createGlobalApplicationCommand(
                payload: .init(name: commandName, description: commandDesc)
            ).decode()
            
            XCTAssertEqual(command.name, commandName)
            XCTAssertEqual(command.description, commandDesc)
            
            let commandsCount = try await cacheClient.getGlobalApplicationCommands().decode().count
            
            let deletionResponse = try await cacheClient.deleteGlobalApplicationCommand(
                commandId: command.id
            )
            
            XCTAssertEqual(deletionResponse.status, .noContent)
            
            let newCommandsCount = try await cacheClient.getGlobalApplicationCommands()
                .decode().count
            
            XCTAssertEqual(commandsCount, newCommandsCount)
        }
        
        /// Because `ClientCache`s are shared across different `DefaultDiscordClient`s.
        /// This is to make sure the last test doesn't have impact on the next tests.
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        /// Caching enabled, but with exception, so disabled
        do {
            let cachingBehavior = ClientConfiguration.CachingBehavior.custom(
                defaultTTL: 2,
                endpoints: [.getGlobalApplicationCommands: 0]
            )
            let configuration = ClientConfiguration(cachingBehavior: cachingBehavior)
            let cacheClient: any DiscordClient = DefaultDiscordClient(
                httpClient: httpClient,
                token: Constants.token,
                appId: Constants.botId,
                configuration: configuration
            )
            
            /// We create a command, fetch the commands count, then delete the command
            /// and fetch the command count again.
            /// Since we are not using caching for this endpoint, the first command count and
            /// the second command count must NOT be the same.
            let commandName = "test-command"
            let commandDesc = "Testing!"
            let command = try await cacheClient.createGlobalApplicationCommand(
                payload: .init(name: commandName, description: commandDesc)
            ).decode()
            
            XCTAssertEqual(command.name, commandName)
            XCTAssertEqual(command.description, commandDesc)
            
            let commandsCount = try await cacheClient.getGlobalApplicationCommands().decode().count
            
            let deletionResponse = try await cacheClient.deleteGlobalApplicationCommand(
                commandId: command.id
            )
            
            XCTAssertEqual(deletionResponse.status, .noContent)
            
            let newCommandsCount = try await cacheClient
                .getGlobalApplicationCommands()
                .decode()
                .count
            
            XCTAssertEqual(commandsCount, newCommandsCount + 1)
        }
        
        /// Caching disabled
        do {
            let configuration = ClientConfiguration(cachingBehavior: .disabled)
            let cacheClient: any DiscordClient = DefaultDiscordClient(
                httpClient: httpClient,
                token: Constants.token,
                appId: Constants.botId,
                configuration: configuration
            )
            
            /// We create a command, fetch the commands count, then delete the command
            /// and fetch the command count again.
            /// Since we are not using caching, the first command count and the second
            /// command count must NOT be the same.
            let commandName = "test-command"
            let commandDesc = "Testing!"
            let command = try await cacheClient.createGlobalApplicationCommand(
                payload: .init(name: commandName, description: commandDesc)
            ).decode()
            
            XCTAssertEqual(command.name, commandName)
            XCTAssertEqual(command.description, commandDesc)
            
            let commandsCount = try await cacheClient.getGlobalApplicationCommands().decode().count
            
            /// I think the command-addition takes effect a second or so later, so we need to
            /// wait a second before we try to delete the command, otherwise Discord might
            /// think the command doesn't exist and return 404.
            try await Task.sleep(nanoseconds: 1_000_000_000)
            
            let deletionResponse = try await cacheClient.deleteGlobalApplicationCommand(
                commandId: command.id
            )
            
            XCTAssertEqual(deletionResponse.status, .noContent)
            
            let newCommandsCount = try await cacheClient
                .getGlobalApplicationCommands()
                .decode()
                .count
            
            XCTAssertEqual(commandsCount, newCommandsCount + 1)
        }
    }
}

private actor Container {
    private var counter = 0
    private var targetCounter: Int
    
    init(targetCounter: Int) {
        self.targetCounter = targetCounter
    }
    
    func increaseCounter() {
        counter += 1
        if counter == targetCounter {
            waiter?.resume()
            waiter = nil
        }
    }
    
    private var waiter: CheckedContinuation<(), Never>?
    
    func waitForCounter() async {
        Task {
            try await Task.sleep(nanoseconds: 10_000_000_000)
            if waiter != nil {
                waiter?.resume()
                waiter = nil
                XCTFail("Failed to test in-time")
            }
        }
        await withCheckedContinuation {
            waiter = $0
        }
    }
}
