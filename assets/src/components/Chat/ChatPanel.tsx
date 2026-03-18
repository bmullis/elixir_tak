import {
  useCallback,
  useEffect,
  useMemo,
  useState,
  type FormEvent,
} from "react";
import { useDashboardStore } from "../../store";
import { groupColor } from "../../types";
import { getChannel } from "../../hooks/useChannel";
import { Badge, Button, Input, PanelHeader } from "../ui";
import { MessageSquare } from "lucide-react";
import { formatTime } from "../../utils/formatting";
import styles from "./ChatPanel.module.css";

/** Right-side chat panel -- document-flow element that pushes content left when open */
export default function ChatPanel() {
  const open = useDashboardStore((s) => s.chatOpen);
  const chatMessages = useDashboardStore((s) => s.chatMessages);
  const chatrooms = useDashboardStore((s) => s.chatrooms);
  const selectedChatroom = useDashboardStore((s) => s.selectedChatroom);
  const toggleChat = useDashboardStore((s) => s.toggleChat);
  const setChatroom = useDashboardStore((s) => s.setChatroom);
  const resetUnread = useDashboardStore((s) => s.resetUnread);

  const [input, setInput] = useState("");
  const callsign = useDashboardStore((s) => s.identity.callsign);

  // Filter messages by chatroom
  const filtered = useMemo(() => {
    if (!selectedChatroom) return chatMessages;
    return chatMessages.filter((m) => m.chatroom === selectedChatroom);
  }, [chatMessages, selectedChatroom]);

  // Sorted chatroom list
  const roomList = useMemo(
    () => Array.from(chatrooms).sort(),
    [chatrooms]
  );

  // Reset unread when panel opens
  useEffect(() => {
    if (open) resetUnread();
  }, [open, resetUnread]);

  const handleSend = useCallback(
    (e: FormEvent) => {
      e.preventDefault();
      const msg = input.trim();
      if (!msg) return;

      const channel = getChannel();
      if (!channel) return;

      channel.push("send_chat", { message: msg, callsign });
      setInput("");
    },
    [input, callsign]
  );

  // Close on Escape
  useEffect(() => {
    if (!open) return;
    const handler = (e: KeyboardEvent) => {
      if (e.key === "Escape") toggleChat();
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [open, toggleChat]);

  return (
    <div className={`${styles.panel} ${open ? styles.panelOpen : ""}`}>
      <div className={styles.inner}>
        <PanelHeader title="Chat" onClose={toggleChat} />

        {/* Chatroom filter */}
        {roomList.length > 0 && (
          <div className={styles.roomFilter}>
            <Badge
              variant={selectedChatroom === null ? "accent" : "default"}
              size="md"
              className={styles.roomChip}
              onClick={() => setChatroom(null)}
            >
              All
            </Badge>
            {roomList.map((room) => (
              <Badge
                key={room}
                variant={selectedChatroom === room ? "accent" : "default"}
                size="md"
                className={styles.roomChip}
                onClick={() => setChatroom(room)}
              >
                {room}
              </Badge>
            ))}
          </div>
        )}

        {/* Messages */}
        <div className={styles.messages}>
          {filtered.length === 0 ? (
            <div className={styles.empty}>No messages yet</div>
          ) : (
            [...filtered].reverse().map((msg) => (
              <MessageBubble key={msg.uid} msg={msg} />
            ))
          )}
        </div>

        {/* Send form */}
        <form className={styles.sendForm} onSubmit={handleSend}>
          <Input
            inputSize="sm"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            placeholder="Type a message..."
            className={styles.sendInput}
          />
          <Button
            variant="primary"
            size="sm"
            mono
            type="submit"
            disabled={!input.trim()}
          >
            Send
          </Button>
        </form>
      </div>
    </div>
  );
}

/** Floating chat FAB -- absolutely positioned bottom-right */
export function ChatFab() {
  const chatOpen = useDashboardStore((s) => s.chatOpen);
  const unreadCount = useDashboardStore((s) => s.unreadCount);
  const toggleChat = useDashboardStore((s) => s.toggleChat);

  if (chatOpen) return null;

  return (
    <button
      className={styles.fab}
      onClick={toggleChat}
      aria-label="Open chat"
    >
      <MessageSquare size={22} />
      {unreadCount > 0 && (
        <span className={styles.fabBadge}>
          {unreadCount > 99 ? "99+" : unreadCount}
        </span>
      )}
    </button>
  );
}

// -- Message sub-component -----------------------------------------------

function MessageBubble({ msg }: { msg: import("../../types").ChatMessage }) {
  const color = groupColor(msg.group);

  return (
    <div className={styles.message}>
      <div className={styles.messageMeta}>
        <span className={styles.senderName}>{msg.sender}</span>
        {msg.group && (
          <span
            className={styles.groupBadge}
            style={{
              background: `color-mix(in srgb, ${color} 20%, transparent)`,
              color,
            }}
          >
            {msg.group}
          </span>
        )}
        <span className={styles.timestamp}>{formatTime(msg.time, { hour: "2-digit", minute: "2-digit" })}</span>
      </div>
      <div className={styles.messageText}>{msg.message}</div>
    </div>
  );
}
