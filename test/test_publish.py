#!/usr/bin/env python3
"""
Script pour publier un message de test dans RabbitMQ
Usage: python3 test_publish.py [topic_kind] [topic_id] [message_type]

Exemples:
  python3 test_publish.py user user-123 unread_notifications
  python3 test_publish.py text-channel channel-456 message_created
  python3 test_publish.py  # Utilise les valeurs par défaut
"""

import sys
import json
import os
from datetime import datetime
import time

try:
    import pika
except ImportError:
    print("❌ Erreur: pika n'est pas installé")
    print("💡 Installe-le avec: pip3 install pika")
    sys.exit(1)


def parse_rabbitmq_url(url):
    """Parse une URL RabbitMQ et retourne les paramètres de connexion"""
    if not url.startswith("amqp://"):
        raise ValueError("URL doit commencer par amqp://")
    
    # Enlever le préfixe amqp://
    url = url[7:]
    
    # Séparer credentials et host
    if "@" in url:
        creds_part, host_part = url.split("@", 1)
        user, password = creds_part.split(":", 1)
    else:
        user, password = "guest", "guest"
        host_part = url
    
    # Extraire host et port
    if ":" in host_part:
        host, port = host_part.split(":", 1)
        port = int(port)
    else:
        host = host_part
        port = 5672
    
    return {
        "host": host,
        "port": port,
        "username": user,
        "password": password
    }


def create_message(topic_kind, topic_id, message_type):
    """Crée un message de test"""
    message_id = f"test-{int(time.time())}-{os.getpid()}"
    occurred_at = datetime.utcnow().isoformat() + "Z"
    
    return {
        "id": message_id,
        "type": message_type,
        "occurred_at": occurred_at,
        "source": "test-script",
        "version": 1,
        "topic_kind": topic_kind,
        "topic_id": topic_id,
        "body": {
            "test": True,
            "timestamp": int(time.time()),
            "message": "Message de test depuis le script Python"
        }
    }


def publish_message(queue, message, connection_params):
    """Publie un message dans RabbitMQ"""
    try:
        print("🔌 Connexion à RabbitMQ...")
        connection = pika.BlockingConnection(
            pika.ConnectionParameters(
                host=connection_params["host"],
                port=connection_params["port"],
                credentials=pika.PlainCredentials(
                    connection_params["username"],
                    connection_params["password"]
                )
            )
        )
        channel = connection.channel()
        
        print("✅ Connecté à RabbitMQ")
        
        # Déclarer la queue (durable)
        channel.queue_declare(queue=queue, durable=True)
        print(f"✅ Queue '{queue}' déclarée")
        
        # Publier le message
        channel.basic_publish(
            exchange='',
            routing_key=queue,
            body=json.dumps(message),
            properties=pika.BasicProperties(
                delivery_mode=2,  # Rendre le message persistant
            )
        )
        
        print("✅ Message publié avec succès!")
        print(f"   ID: {message['id']}")
        print(f"   Type: {message['type']}")
        print(f"   Topic: {message['topic_kind']}:{message['topic_id']}")
        print(f"   Timestamp: {message['occurred_at']}")
        
        connection.close()
        return True
        
    except pika.exceptions.AMQPConnectionError as e:
        print(f"❌ Erreur de connexion: {e}")
        print("💡 Assure-toi que RabbitMQ est démarré:")
        print("   docker-compose -f docker-compose.rabbitmq.yml up -d")
        return False
    except Exception as e:
        print(f"❌ Erreur: {e}")
        return False


def main():
    # Configuration
    rabbitmq_url = os.getenv("RABBITMQ_URL", "amqp://guest:guest@localhost:5672")
    queue = os.getenv("QUEUE", "notification")
    
    # Arguments optionnels
    topic_kind = sys.argv[1] if len(sys.argv) > 1 else "user"
    topic_id = sys.argv[2] if len(sys.argv) > 2 else "user-123"
    message_type = sys.argv[3] if len(sys.argv) > 3 else "test_event"
    
    print("📋 Configuration:")
    print(f"   Queue: {queue}")
    print(f"   Topic: {topic_kind}:{topic_id}")
    print(f"   Type: {message_type}")
    print()
    
    # Parser l'URL RabbitMQ
    try:
        connection_params = parse_rabbitmq_url(rabbitmq_url)
    except Exception as e:
        print(f"❌ Erreur lors du parsing de l'URL: {e}")
        sys.exit(1)
    
    # Créer le message
    message = create_message(topic_kind, topic_id, message_type)
    
    # Publier
    success = publish_message(queue, message, connection_params)
    
    if success:
        print()
        print("📋 Vérifie les logs de l'application pour voir si le message a été traité")
        print("🌐 Ou va sur http://localhost:15672 pour voir la queue")
        print()
        print("Message JSON:")
        print(json.dumps(message, indent=2))
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()

