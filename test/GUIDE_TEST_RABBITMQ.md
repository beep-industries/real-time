# Guide : Tester avec de vrais messages RabbitMQ

## 1. Démarrer RabbitMQ

```bash
docker-compose -f docker-compose.rabbitmq.yml up -d
```

Vérifier que c'est démarré :

```bash
docker ps | grep rabbitmq
```

## 2. Voir les messages dans la queue (Interface Web)

### Accéder à l'interface RabbitMQ

1. **Ouvrir dans le navigateur** : <http://localhost:15672>
2. **Se connecter** :
   - Username: `guest`
   - Password: `guest`

### Naviguer vers la queue

1. Cliquer sur **"Queues"** dans le menu de gauche
2. Chercher la queue **`notification`**
3. Cliquer dessus pour voir les détails

### Informations visibles

- **Messages Ready** : Messages en attente de consommation
- **Messages Unacked** : Messages en cours de traitement
- **Get messages** : Bouton pour voir les messages dans la queue
- **Publish message** : Bouton pour publier un message de test directement

### Publier un message depuis l'interface web

1. Dans la page de la queue `notification`, cliquer sur **"Publish message"**
2. Dans **"Payload"**, coller ce JSON :

```json
{
  "id": "test-123-456",
  "type": "unread_notifications",
  "occurred_at": "2024-01-15T10:30:00Z",
  "source": "notifications",
  "version": 1,
  "topic_kind": "user",
  "topic_id": "user-123",
  "body": {
    "unread": 5,
    "message": "Vous avez 5 nouvelles notifications"
  }
}
```

3. Cliquer sur **"Publish message"**
4. Le message devrait disparaître rapidement (consommé par ton application)

## 3. Tester depuis IEx (Recommandé)

### Démarrer l'application

```bash
iex -S mix phx.server
```

### Vérifier que le consumer est connecté

```elixir
BeepRealTime.Queue.Consumer.status()
# => {true, %{}} si connecté
```

### Publier un message de test

```elixir
# Ouvrir une connexion RabbitMQ
{:ok, connection} = AMQP.Connection.open("amqp://guest:guest@localhost:5672")
{:ok, channel} = AMQP.Channel.open(connection)

# S'assurer que la queue existe
AMQP.Queue.declare(channel, "notification", durable: true)

# Créer un message de test (format attendu par le Dispatcher)
message = %{
  "id" => "550e8400-e29b-41d4-a716-446655440000",
  "type" => "unread_notifications",
  "occurred_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
  "source" => "notifications",
  "version" => 1,
  "topic_kind" => "user",
  "topic_id" => "user-123",
  "body" => %{
    "unread" => 5,
    "message" => "Vous avez 5 nouvelles notifications"
  }
}
```

## 4. Scripts de test rapide

### Utilisation

```bash
# Message par défaut
python3 test_publish.py

# Message personnalisé
python3 test_publish.py user user-456 unread_notifications
python3 test_publish.py text-channel channel-789 message_created
```
