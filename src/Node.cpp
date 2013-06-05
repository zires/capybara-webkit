#include "Node.h"
#include "WebPage.h"
#include "WebPageManager.h"
#include "InvocationResult.h"
#include "ErrorMessage.h"

Node::Node(WebPageManager *manager, QStringList &arguments, QObject *parent) : JavascriptCommand(manager, arguments, parent) {
}

void Node::start() {
  QStringList functionArguments(arguments());
  QString functionName = functionArguments.takeFirst();
  if (isAttached(functionArguments)) {
    InvocationResult result = page()->invokeCapybaraFunction(functionName, functionArguments);
    finish(&result);
  } else {
    ErrorMessage *error = new ErrorMessage(
      "NodeNotAttachedError",
      "Node not attached"
    );
    Command::finish(false, error);
  }
}

QString Node::toString() const {
  QStringList functionArguments(arguments());
  return QString("Node.") + functionArguments.takeFirst();
}

bool Node::isAttached(QStringList &arguments) {
  return page()->invokeCapybaraFunction("isAttached", arguments).result().toBool();
}
