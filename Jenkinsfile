pipeline {
    agent any
    tools {
        terraform 'terraform'
    }
    options {
        // Local state has no locking, so never run two builds against it at once
        disableConcurrentBuilds()
    }
    parameters {
        choice(name: 'action', choices: ['apply', 'destroy'], description: 'Select the action to perform')
    }
    environment {
        SLACKCHANNEL = '21th_sept_2026_sock_shop_kubeadm_project'
        SLACKCREDENTIALS = credentials('slack-cred')
    }
   
    stages {
        stage('IAC Scan') {
            steps {
                script {
                    // Install for the jenkins user and run via python3 -m (~/.local/bin is not on PATH)
                    sh 'python3 -m pip install --user --upgrade checkov'
                    // Print results to the console and write a JUnit XML report
                    def checkovStatus = sh(script: 'python3 -m checkov.main -d . --framework terraform --skip-path "\\.terraform" -o cli -o junitxml --output-file-path console,checkov-report --quiet', returnStatus: true)
                    junit allowEmptyResults: true, testResults: 'checkov-report/results_junitxml.xml'
                    archiveArtifacts artifacts: 'checkov-report/*', allowEmptyArchive: true
                    // if (checkovStatus != 0) {
                    //     error 'Checkov found some issues'
                    // }
                }
            }
        }
        stage('Terraform Init') {  // Fixed spelling
            steps {
                sh 'terraform init'
            }
        }
        stage('Terraform format') {
            steps {
                sh 'terraform fmt --recursive'
            }
        }
        stage('Terraform validate') {
            steps {
                sh 'terraform validate'
            }
        }
        stage('Terraform plan') {
            steps {
                sh 'terraform plan'
            }
        }
        stage('Terraform action') {
            steps {
                script {
                    // params.action is null on the very first build (before Jenkins registers the parameter)
                    if ((params.action ?: 'apply') == 'destroy') {
                        // destroy never updates resources, so turn RDS deletion protection off with an apply first
                        def db = 'module.database.aws_db_instance.team1_mysql_database'
                        sh "terraform untaint ${db} || true"
                        sh "terraform apply -auto-approve -target=${db} -var=db_deletion_protection=false"
                        sh "terraform destroy -auto-approve -var=db_deletion_protection=false"
                    } else {
                        sh "terraform apply -auto-approve"
                    }
                }
            }
        }
    }
    post {
        // One message per build; currentResult is always set (result is null while a successful build is still running)
        always {
            script {
                def colors = [SUCCESS: 'good', UNSTABLE: 'warning']
                slackSend(
                    channel: SLACKCHANNEL,
                    color: colors.get(currentBuild.currentResult, 'danger'),
                    message: "Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' (${params.action ?: 'apply'}) finished: ${currentBuild.currentResult}. Console: ${env.BUILD_URL}"
                )
            }
        }
    }
}
 
