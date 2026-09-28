<?php
namespace OCA\UmamiVue\AppInfo;

use OCP\AppFramework\App;
use OCP\Util;

class Application extends App {
    public function __construct(array $urlParams = []) {
        parent::__construct('umami_vue', $urlParams);
        Util::addScript('umami_vue', 'main');
    }
}
