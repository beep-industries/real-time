#!/usr/bin/env python3
"""
Test script to verify RabbitMQ exchange bindings are working correctly.

This script:
1. Publishes a test message to the 'messages.events' exchange
2. Verifies the message is consumed by checking application logs

Prerequisites:
- RabbitMQ running (docker-compose -f docker-compose.rabbitmq.yml up -d)
- Application running (iex -S mix phx.server)
- pika installed (pip install pika)

Usage:
    python3 test_exchange_binding.py
"""

import sys
import json
import time
from datetime import datetime

try:
    import pika
except ImportError:
    print("❌ Error: pika is not installed")
    print("💡 Install it with: pip3 install pika")
    sys.exit(1)


def test_notifications_exchange():
    """Test publishing to notifications exchange"""
    print("\n" + "="*60)
    print("Testing 'notifications' exchange binding")
    print("="*60)
    
    try:
        # Connect to RabbitMQ
        print("🔌 Connecting to RabbitMQ...")
        connection = pika.BlockingConnection(
            pika.ConnectionParameters(host='localhost', port=5672)
        )
        channel = connection.channel()
        print("✅ Connected to RabbitMQ\n")
        
        # Create test message
        message = {
            "id": f"test-notifications-{int(time.time())}",
            "type": "unread_notifications",
            "occurred_at": datetime.utcnow().isoformat() + "Z",
            "source": "test-script",
            "version": 1,
            "topic_kind": "user",
            "topic_id": "user-123",
            "body": {
                "unread": 5,
                "message": "Test notification from notifications exchange"
            }
        }
        
        # Publish to notifications exchange
        print("📤 Publishing message to 'notifications' exchange...")
        print(f"   Routing key: notifications.test")
        print(f"   Message ID: {message['id']}\n")
        
        channel.basic_publish(
            exchange='notifications',
            routing_key='notifications.test',
            body=json.dumps(message),
            properties=pika.BasicProperties(
                delivery_mode=2,  # Make message persistent
            )
        )
        
        print("✅ Message published to 'notifications' exchange")
        print("💡 Check application logs for consumption confirmation\n")
        
        connection.close()
        return True
        
    except Exception as e:
        print(f"❌ Error: {e}")
        return False


def test_messages_events_exchange():
    """Test publishing to messages.events exchange"""
    print("\n" + "="*60)
    print("Testing 'messages.events' exchange binding")
    print("="*60)
    
    try:
        # Connect to RabbitMQ
        print("🔌 Connecting to RabbitMQ...")
        connection = pika.BlockingConnection(
            pika.ConnectionParameters(host='localhost', port=5672)
        )
        channel = connection.channel()
        print("✅ Connected to RabbitMQ\n")
        
        # Create test CreateMessageEvent (simplified, real one would be Protobuf)
        message = {
            "message_id": f"msg-{int(time.time())}",
            "channel_id": "channel-123",
            "author_id": "user-456",
            "content": "Test message from messages.events exchange",
            "reply_to_message_id": None,
            "attachments": [],
            "notify_entries": []
        }
        
        # Publish to messages.events exchange
        print("📤 Publishing message to 'messages.events' exchange...")
        print(f"   Routing key: messages.create")
        print(f"   Message ID: {message['message_id']}\n")
        
        channel.basic_publish(
            exchange='messages.events',
            routing_key='messages.create',
            body=json.dumps(message),
            properties=pika.BasicProperties(
                delivery_mode=2,  # Make message persistent
                headers={'event_type': 'messages.create'}
            )
        )
        
        print("✅ Message published to 'messages.events' exchange")
        print("💡 Check application logs for consumption confirmation\n")
        
        connection.close()
        return True
        
    except Exception as e:
        print(f"❌ Error: {e}")
        return False


def check_exchange_exists(exchange_name):
    """Verify that an exchange exists"""
    try:
        connection = pika.BlockingConnection(
            pika.ConnectionParameters(host='localhost', port=5672)
        )
        channel = connection.channel()
        
        # Try to declare exchange passively (will fail if doesn't exist)
        channel.exchange_declare(
            exchange=exchange_name,
            exchange_type='topic',
            passive=True,
            durable=True
        )
        
        connection.close()
        return True
    except Exception:
        return False


def main():
    print("\n" + "="*60)
    print("RabbitMQ Exchange Binding Test Script")
    print("="*60)
    
    # Check if RabbitMQ is accessible
    try:
        connection = pika.BlockingConnection(
            pika.ConnectionParameters(host='localhost', port=5672)
        )
        connection.close()
        print("✅ RabbitMQ is accessible\n")
    except Exception as e:
        print(f"❌ Cannot connect to RabbitMQ: {e}")
        print("💡 Make sure RabbitMQ is running:")
        print("   docker-compose -f docker-compose.rabbitmq.yml up -d")
        sys.exit(1)
    
    # Check if exchanges exist
    print("Checking for exchanges...")
    notifications_exists = check_exchange_exists('notifications')
    messages_events_exists = check_exchange_exists('messages.events')
    
    if notifications_exists:
        print("✅ 'notifications' exchange exists")
    else:
        print("⚠️  'notifications' exchange does not exist yet")
        print("   It will be created when the application starts")
    
    if messages_events_exists:
        print("✅ 'messages.events' exchange exists")
    else:
        print("⚠️  'messages.events' exchange does not exist yet")
        print("   It will be created when the application starts")
    
    if not (notifications_exists and messages_events_exists):
        print("\n💡 Start the application first:")
        print("   iex -S mix phx.server")
        print("\nThe exchanges will be automatically created on startup.")
        sys.exit(1)
    
    # Run tests
    success = True
    success = test_notifications_exchange() and success
    success = test_messages_events_exchange() and success
    
    # Summary
    print("\n" + "="*60)
    print("TEST SUMMARY")
    print("="*60)
    if success:
        print("✅ All messages published successfully!")
        print("\n📋 Next steps:")
        print("1. Check the application logs for:")
        print("   - 'Queue notification bound to exchanges: notifications, messages.events'")
        print("   - Message consumption logs")
        print("2. Check RabbitMQ management UI (http://localhost:15672)")
        print("   - Navigate to Queues → notification")
        print("   - Check the Bindings section")
    else:
        print("❌ Some tests failed")
        print("💡 Check RabbitMQ and application logs for errors")
    print("="*60 + "\n")


if __name__ == "__main__":
    main()
