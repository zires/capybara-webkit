#include "Command.h"

class WebPage;

class Authenticate : public Command {
  Q_OBJECT

  public:
    Authenticate(WebPage *page, QStringList &arguments, QObject *parent = 0);
    virtual void start();
};

