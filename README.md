# zigup

## Zig update and installation system
zigup is an automatic update / installing system for the Zig programming language

> :warning: **This version only works on Linux at the moment.**

## Install zigup
```
$ curl -fsSL https://tinyurl.com/zigup | sh
```

## Usage
Upgrade to a newer version:
```
$ sudo zigup upgrade
```

Install zig latest stable release: 
```
$ sudo zigup install
```

Install a specific zig version: 
```
$ sudo zigup install --version 0.13.0
```

Display zig and zigup current versions: 
```
$ zigup --version
```

## License
MIT [License](LICENSE)

Copyright © 2025 Gabriel Pacheco
