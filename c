import os

base = r'c:\Projects\anti new project'

# Fix developer_settings_screen.dart - needs one more )
f = os.path.join(base, r'lib\screens\settings\developer_settings_screen.dart')
with open(f, 'r', encoding='utf-8') as fh:
    content = fh.read()

lines = content.split('\n')
for i in range(len(lines) - 1, 0, -1):
    stripped = lines[i].strip()
    if stripped == ');':
        # Check if previous line ends with ),
        if i > 0 and lines[i-1].rstrip().endswith('),'):
            lines[i] = '  );'
            lines.insert(i, '    )')
            break
        else:
            lines[i] = '    ),'
            lines.insert(i + 1, '  );')
            break

content = '\n'.join(lines)
with open(f, 'w', encoding='utf-8') as fh:
    fh.write(content)

opens = content.count('(')
closes = content.count(')')
print(f'developer_settings_screen.dart: opens={opens}, closes={closes}, diff={opens-closes}')

# Fix manage_plans_screen.dart - needs one more )
f = os.path.join(base, r'lib\screens\settings\manage_plans_screen.dart')
with open(f, 'r', encoding='utf-8') as fh:
    content = fh.read()

# First fix literal \n issues
content = content.replace('\\\\n', '\n')

lines = content.split('\n')
for i in range(len(lines) - 1, 0, -1):
    stripped = lines[i].strip()
    if stripped == ');':
        lines[i] = '    ),'
        lines.insert(i + 1, '  );')
        break

content = '\n'.join(lines)
with open(f, 'w', encoding='utf-8') as fh:
    fh.write(content)

opens = content.count('(')
closes = content.count(')')
print(f'manage_plans_screen.dart: opens={opens}, closes={closes}, diff={opens-closes}')

# Also fix the remaining error files
remaining_files = [
    r'lib\screens\settings\privacy_controls_screen.dart',
    r'lib\screens\wallet\subscription_screen.dart',
    r'lib\screens\wallet\wallet_history_screen.dart',
    r'lib\screens\profile\collection_detail_screen.dart',
]

for rel in remaining_files:
    f = os.path.join(base, rel)
    if not os.path.exists(f):
        continue
    with open(f, 'r', encoding='utf-8') as fh:
        content = fh.read()
    # Fix literal \n
    content = content.replace('\\\\n', '\n')
    with open(f, 'w', encoding='utf-8') as fh:
        fh.write(content)
    opens = content.count('(')
    closes = content.count(')')
    print(f'{os.path.basename(rel)}: opens={opens}, closes={closes}, diff={opens-closes}')

print('Done!')
