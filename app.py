from flask import Flask, render_template
app = Flask(__name__)


@app.route('/')
def main_page():
    return render_template('index.html')

@app.route('/health')
def health_check_page():
    return 'OK'


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
